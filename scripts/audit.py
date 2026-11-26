#!/usr/bin/env python3
"""
Auditoría de cumplimiento del repositorio order-manager.

Revisa reglas de seguridad y buenas prácticas antes de construir y desplegar:
  1. Secretos      - no hay claves, tokens ni llaves privadas escritas en el código
  2. Dockerfile    - la imagen final no corre como root y las imágenes base tienen versión fija
  3. Kubernetes    - cada contenedor tiene límites de recursos, probes y (si es nuestra imagen) corre sin root
  4. Docker Compose- cada servicio tiene límite de memoria y la base de datos no queda expuesta hacia afuera
  5. Pipeline      - el workflow declara permisos mínimos y usa acciones con versión fija

Cada hallazgo es ERROR (bloquea el pipeline) o ADVERTENCIA (se informa, no bloquea).
Uso:  python3 scripts/audit.py        (sale con código 1 si hay algún ERROR)
"""
import glob
import os
import re
import subprocess
import sys

import yaml

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
os.chdir(ROOT)

results = []  # (regla, nivel, archivo, detalle)   nivel: OK / ERROR / ADVERTENCIA


def add(rule, level, file, detail):
    results.append((rule, level, file, detail))


def tracked_files():
    """Archivos versionados en git (si no hay git, todos los del directorio)."""
    try:
        out = subprocess.run(["git", "ls-files"], capture_output=True, text=True, check=True).stdout
        return [f for f in out.splitlines() if f]
    except Exception:
        return [os.path.relpath(p, ROOT) for p in glob.glob("**/*", recursive=True) if os.path.isfile(p)]


def load_yaml_docs(path):
    with open(path, encoding="utf-8") as fh:
        return [d for d in yaml.safe_load_all(fh) if d]


# ---------------------------------------------------------------------------
# 1. Secretos escritos en el código
# ---------------------------------------------------------------------------
SECRET_PATTERNS = [
    ("llave privada", re.compile(r"-----BEGIN [A-Z ]*PRIVATE KEY-----")),
    ("access key de AWS", re.compile(r"\bAKIA[0-9A-Z]{16}\b")),
    ("token de GitHub", re.compile(r"\bgh[pousr]_[A-Za-z0-9]{36,}\b")),
    ("token de Slack", re.compile(r"\bxox[baprs]-[A-Za-z0-9-]{10,}\b")),
]
# clave = valor donde la clave suena a secreto (password, secret, token, api key)
KEY_VALUE = re.compile(
    r"(?i)^\s*-?\s*([\w.\-]*(?:password|passwd|secret|token|api[_-]?key)[\w.\-]*)\s*[:=]\s*(.*)$"
)
CODE_EXT = (".properties", ".yml", ".yaml", ".java", ".xml", ".json", ".sh", ".ps1", ".py", ".conf")


def value_is_safe(value):
    v = value.strip().strip('"').strip("'").strip()
    v = re.split(r"\s+#", v)[0].strip()
    if v == "" or v.lower() in ("true", "false", "null", "none"):
        return True
    # referencias a variables de entorno o a secrets del pipeline: ${VAR}, $VAR, ${{ secrets.X }}
    if v.startswith("$"):
        return True
    # bloques de YAML que se completan en la línea siguiente (valueFrom, secretKeyRef, etc.)
    if v in ("|", ">", "{}", "[]"):
        return True
    return False


def check_secrets(files):
    found = 0
    env_files = [f for f in files if re.search(r"(^|/)\.env(\.|$)", f)]
    for f in env_files:
        add("Secretos", "ERROR", f, "archivo .env versionado en git (debe ir en .gitignore)")
        found += 1

    for f in files:
        if not (f.endswith(CODE_EXT) or os.path.basename(f) == "Dockerfile"):
            continue
        if f.startswith("scripts/audit.py"):
            continue
        try:
            lines = open(f, encoding="utf-8").read().splitlines()
        except (UnicodeDecodeError, FileNotFoundError):
            continue
        for n, line in enumerate(lines, 1):
            stripped = line.strip()
            if stripped.startswith(("#", "//", "*", "<!--")):
                continue
            for name, pat in SECRET_PATTERNS:
                if pat.search(line):
                    add("Secretos", "ERROR", f"{f}:{n}", f"posible {name} escrita en el código")
                    found += 1
            m = KEY_VALUE.match(line)
            # "id-token: write" es un permiso de GitHub Actions (login por OIDC), no un secreto
            if m and m.group(1) == "id-token":
                continue
            if m and not value_is_safe(m.group(2)):
                add("Secretos", "ERROR", f"{f}:{n}",
                    f"'{m.group(1)}' tiene un valor escrito en el código; debe venir de una variable de entorno o secret")
                found += 1
    if found == 0:
        add("Secretos", "OK", "repositorio", "no hay claves, tokens ni llaves privadas escritas en el código")


# ---------------------------------------------------------------------------
# 2. Dockerfile
# ---------------------------------------------------------------------------
def check_dockerfile():
    path = "Dockerfile"
    if not os.path.exists(path):
        add("Dockerfile", "ERROR", path, "no existe Dockerfile")
        return
    lines = [l.strip() for l in open(path, encoding="utf-8") if l.strip() and not l.strip().startswith("#")]

    stages, current = [], []
    for l in lines:
        if l.upper().startswith("FROM "):
            if current:
                stages.append(current)
            current = [l]
        else:
            current.append(l)
    if current:
        stages.append(current)

    ok = True
    for st in stages:
        image = st[0].split()[1]
        if image.lower() == "scratch":
            continue
        if ":" not in image or image.endswith(":latest"):
            add("Dockerfile", "ERROR", path, f"la imagen base '{image}' no tiene versión fija (evitar :latest)")
            ok = False

    final = stages[-1] if stages else []
    users = [l.split(None, 1)[1] for l in final if l.upper().startswith("USER ")]
    if not users:
        add("Dockerfile", "ERROR", path, "la etapa final no define USER: el contenedor correría como root")
        ok = False
    elif users[-1].split(":")[0] in ("root", "0"):
        add("Dockerfile", "ERROR", path, f"la etapa final corre como root (USER {users[-1]})")
        ok = False

    for l in lines:
        if re.match(r"(?i)^ADD\s+https?://", l):
            add("Dockerfile", "ADVERTENCIA", path, "ADD con URL remota; preferir descargar con verificación de checksum")
        if re.match(r"(?i)^(ENV|ARG)\s+\S*(PASSWORD|SECRET|TOKEN)", l):
            add("Dockerfile", "ERROR", path, f"secreto definido en la imagen: {l}")
            ok = False
    if ok:
        add("Dockerfile", "OK", path, f"usuario sin privilegios (USER {users[-1]}) e imágenes base con versión fija")


# ---------------------------------------------------------------------------
# 3. Manifiestos de Kubernetes
# ---------------------------------------------------------------------------
WORKLOADS = ("Deployment", "StatefulSet", "DaemonSet")
OWN_IMAGES = ("order-manager",)  # imágenes que construimos nosotros: deben correr sin root


def check_kubernetes():
    files = sorted(glob.glob("k8s/*.yaml") + glob.glob("k8s/*.yml"))
    if not files:
        add("Kubernetes", "ADVERTENCIA", "k8s/", "no hay manifiestos")
        return
    for f in files:
        for doc in load_yaml_docs(f):
            if doc.get("kind") not in WORKLOADS:
                continue
            name = doc["metadata"]["name"]
            pod = doc["spec"]["template"]["spec"]
            pod_sc = pod.get("securityContext") or {}
            for c in pod.get("containers", []):
                where = f"{f} ({doc['kind']}/{name}, contenedor {c['name']})"
                problems = []
                image = c.get("image", "")
                if ":" not in image or image.endswith(":latest"):
                    problems.append(("ERROR", f"imagen '{image}' sin versión fija"))
                res = c.get("resources") or {}
                for kind in ("requests", "limits"):
                    for r in ("cpu", "memory"):
                        if r not in (res.get(kind) or {}):
                            problems.append(("ERROR", f"falta resources.{kind}.{r}"))
                for probe in ("livenessProbe", "readinessProbe"):
                    if probe not in c:
                        problems.append(("ERROR", f"falta {probe}"))

                sc = c.get("securityContext") or {}
                non_root = sc.get("runAsNonRoot", pod_sc.get("runAsNonRoot")) is True
                no_escalation = sc.get("allowPrivilegeEscalation") is False
                own = any(image.split(":")[0].endswith(o) for o in OWN_IMAGES)
                level = "ERROR" if own else "ADVERTENCIA"
                if not non_root:
                    problems.append((level, "no exige runAsNonRoot" +
                                     ("" if own else " (imagen de terceros: su entrypoint arranca como root)")))
                if not no_escalation:
                    problems.append((level, "no bloquea allowPrivilegeEscalation"))

                if problems:
                    for lvl, msg in problems:
                        add("Kubernetes", lvl, where, msg)
                else:
                    add("Kubernetes", "OK", where, "recursos, probes y contenedor sin root")


# ---------------------------------------------------------------------------
# 4. Docker Compose
# ---------------------------------------------------------------------------
DB_PORTS = ("5432", "3306", "27017", "6379")


def check_compose():
    files = [f for f in ("docker-compose.yml", "docker-compose.observability.yml") if os.path.exists(f)]
    for f in files:
        data = load_yaml_docs(f)[0]
        for svc, cfg in (data.get("services") or {}).items():
            where = f"{f} (servicio {svc})"
            ok = True
            limits = (((cfg.get("deploy") or {}).get("resources") or {}).get("limits") or {})
            if "memory" not in limits:
                add("Docker Compose", "ERROR", where, "sin límite de memoria (deploy.resources.limits.memory)")
                ok = False
            # el socket de docker da control total del host: solo se acepta en solo lectura (:ro)
            for v in cfg.get("volumes") or []:
                v = str(v)
                if "docker.sock" in v:
                    if v.endswith(":ro"):
                        add("Docker Compose", "ADVERTENCIA", where, "monta docker.sock en solo lectura (necesario para descubrir contenedores); evitar en producción")
                    else:
                        add("Docker Compose", "ERROR", where, f"monta docker.sock con escritura ({v}); debe ser :ro")
                        ok = False
            for p in cfg.get("ports") or []:
                p = str(p)
                parts = p.split(":")
                host_bound = len(parts) == 3 and parts[0] in ("127.0.0.1", "localhost")
                if parts[-1].split("/")[0] in DB_PORTS and not host_bound:
                    add("Docker Compose", "ERROR", where, f"base de datos expuesta hacia afuera ({p}); usar 127.0.0.1:")
                    ok = False
            if ok:
                add("Docker Compose", "OK", where, "límite de memoria definido y sin base de datos expuesta")


# ---------------------------------------------------------------------------
# 5. Workflow de GitHub Actions
# ---------------------------------------------------------------------------
def check_workflows():
    for f in sorted(glob.glob(".github/workflows/*.yml") + glob.glob(".github/workflows/*.yaml")):
        text = open(f, encoding="utf-8").read()
        wf = yaml.safe_load(text)
        ok = True
        if "permissions" not in wf:
            add("Pipeline", "ERROR", f, "no declara 'permissions' a nivel de workflow (se usarían permisos amplios)")
            ok = False
        triggers = wf.get(True) or wf.get("on") or {}
        if isinstance(triggers, dict) and "pull_request_target" in triggers:
            add("Pipeline", "ADVERTENCIA", f, "usa pull_request_target: revisar que no ejecute código de forks con secrets")
        for m in re.finditer(r"uses:\s*([\w./-]+)@([\w.\-]+)", text):
            if m.group(2) in ("main", "master", "latest"):
                add("Pipeline", "ERROR", f, f"la acción {m.group(1)} usa @{m.group(2)} (sin versión fija)")
                ok = False
        if ok:
            add("Pipeline", "OK", f, "permisos mínimos declarados y acciones con versión fija")


# ---------------------------------------------------------------------------
def main():
    check_secrets(tracked_files())
    check_dockerfile()
    check_kubernetes()
    check_compose()
    check_workflows()

    icon = {"OK": "✅", "ERROR": "❌", "ADVERTENCIA": "⚠️"}
    errors = [r for r in results if r[1] == "ERROR"]
    warnings = [r for r in results if r[1] == "ADVERTENCIA"]

    report = ["## Auditoría de cumplimiento", "",
              f"**Resultado:** {'❌ FALLA' if errors else '✅ APROBADA'} "
              f"({len(errors)} errores, {len(warnings)} advertencias, "
              f"{len([r for r in results if r[1] == 'OK'])} controles OK)", "",
              "| Regla | Nivel | Dónde | Detalle |", "|---|---|---|---|"]
    order = {"ERROR": 0, "ADVERTENCIA": 1, "OK": 2}
    for rule, level, where, detail in sorted(results, key=lambda r: (order[r[1]], r[0])):
        report.append(f"| {rule} | {icon[level]} {level} | `{where}` | {detail} |")
    text = "\n".join(report) + "\n"

    print(text)
    with open("audit-report.md", "w", encoding="utf-8") as fh:
        fh.write(text)
    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary:
        with open(summary, "a", encoding="utf-8") as fh:
            fh.write(text)
    for rule, level, where, detail in errors:
        # anotación visible en la pestaña del PR / run
        print(f"::error title=Auditoría ({rule})::{where}: {detail}")

    sys.exit(1 if errors else 0)


if __name__ == "__main__":
    main()