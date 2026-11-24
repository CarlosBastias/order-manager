package com.example.ordermanager.service;

import com.example.ordermanager.dto.AddItemRequest;
import com.example.ordermanager.dto.CreateOrderRequest;
import com.example.ordermanager.exception.InvalidOrderStateException;
import com.example.ordermanager.exception.OrderNotFoundException;
import com.example.ordermanager.model.Order;
import com.example.ordermanager.model.OrderItem;
import com.example.ordermanager.model.OrderStatus;
import com.example.ordermanager.repository.OrderRepository;
import io.micrometer.core.instrument.Metrics;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;

@Service
public class OrderService {

    private static final Logger log = LoggerFactory.getLogger(OrderService.class);

    private final OrderRepository repository;

    public OrderService(OrderRepository repository) {
        this.repository = repository;
        // se registra el contador al arrancar para que aparezca en 0 en todas las réplicas
        // (si no, una réplica que aún no crea pedidos no mostraría la métrica en Prometheus)
        Metrics.counter("ordermanager.orders.placed");
    }

    // ============================================================
    // CONSULTAS
    // ============================================================

    public List<Order> getAllOrders() {
        return repository.findAll();
    }

    public List<Order> getOrdersByStatus(OrderStatus status) {
        return repository.findByStatus(status);
    }

    public Order getOrderById(Long id) {
        return repository.findById(id)
                .orElseThrow(() -> new OrderNotFoundException(id));
    }

    // ============================================================
    // CREACIÓN
    // ============================================================

    @Transactional
    public Order createOrder(CreateOrderRequest request) {
        Order order = new Order(request.getCustomerName());

        if (request.getItems() != null) {
            for (AddItemRequest itemReq : request.getItems()) {
                order.addItem(new OrderItem(
                        itemReq.getProductName(),
                        itemReq.getQuantity(),
                        itemReq.getUnitPrice()
                ));
            }
        }
        Order saved = repository.save(order);
        // EP3: métricas de negocio -> ordermanager_orders_placed_total y ordermanager_orders_status_changes_total
        Metrics.counter("ordermanager.orders.placed").increment();
        // no se escribe el nombre del cliente en el log (dato personal), solo el id del pedido
        log.info("Pedido {} creado con {} ítems", saved.getId(),
                saved.getItems() == null ? 0 : saved.getItems().size());
        return saved;
    }

    // ============================================================
    // MODIFICACIÓN
    // ============================================================

    @Transactional
    public Order addItem(Long orderId, AddItemRequest request) {
        Order order = getOrderById(orderId);

        if (!order.canBeModified()) {
            throw new InvalidOrderStateException(
                    "Solo se pueden modificar pedidos en estado PENDING. Actual: " + order.getStatus()
            );
        }

        OrderItem item = new OrderItem(
                request.getProductName(),
                request.getQuantity(),
                request.getUnitPrice()
        );
        order.addItem(item);
        return repository.save(order);
    }

    // ============================================================
    // TRANSICIONES
    // ============================================================

    @Transactional
    public Order confirmOrder(Long id) {
        return transitionTo(id, OrderStatus.PENDING, OrderStatus.CONFIRMED);
    }

    @Transactional
    public Order shipOrder(Long id) {
        return transitionTo(id, OrderStatus.CONFIRMED, OrderStatus.SHIPPED);
    }

    @Transactional
    public Order deliverOrder(Long id) {
        return transitionTo(id, OrderStatus.SHIPPED, OrderStatus.DELIVERED);
    }

    @Transactional
    public Order cancelOrder(Long id) {
        Order order = getOrderById(id);

        if (order.getStatus() == OrderStatus.DELIVERED) {
            throw new InvalidOrderStateException(
                    "Un pedido entregado no puede cancelarse"
            );
        }
        if (order.getStatus() == OrderStatus.CANCELLED) {
            throw new InvalidOrderStateException("El pedido ya está cancelado");
        }

        OrderStatus previous = order.getStatus();
        order.setStatus(OrderStatus.CANCELLED);
        Order saved = repository.save(order);
        recordStatusChange(id, previous, OrderStatus.CANCELLED);
        return saved;
    }

    // ============================================================
    // AUXILIAR
    // ============================================================

    private Order transitionTo(Long id, OrderStatus expected, OrderStatus target) {
        Order order = getOrderById(id);

        if (order.getStatus() != expected) {
            throw new InvalidOrderStateException(
                    order.getStatus().name(),
                    target.name()
            );
        }

        order.setStatus(target);
        Order saved = repository.save(order);
        recordStatusChange(id, expected, target);
        return saved;
    }

    private void recordStatusChange(Long id, OrderStatus from, OrderStatus to) {
        Metrics.counter("ordermanager.orders.status.changes", "to", to.name()).increment();
        log.info("Pedido {} cambió de {} a {}", id, from, to);
    }

    // ============================================================
    // ELIMINACIÓN
    // ============================================================

    @Transactional
    public void deleteOrder(Long id) {
        if (!repository.existsById(id)) {
            throw new OrderNotFoundException(id);
        }
        repository.deleteById(id);
        log.info("Pedido {} eliminado", id);
    }
}