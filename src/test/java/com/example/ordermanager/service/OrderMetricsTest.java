package com.example.ordermanager.service;

import com.example.ordermanager.dto.CreateOrderRequest;
import com.example.ordermanager.model.Order;
import com.example.ordermanager.repository.OrderRepository;
import io.micrometer.core.instrument.Metrics;
import io.micrometer.core.instrument.simple.SimpleMeterRegistry;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.util.Optional;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.when;

/**
 * Comprueba que el servicio registra las métricas de negocio que después
 * se ven en Prometheus/Grafana (pedidos creados y cambios de estado).
 */
@ExtendWith(MockitoExtension.class)
@DisplayName("OrderService - Métricas de negocio")
class OrderMetricsTest {

    @Mock
    private OrderRepository repository;

    @InjectMocks
    private OrderService service;

    // registro en memoria que se conecta al registro global solo durante la prueba
    private SimpleMeterRegistry registry;

    @BeforeEach
    void setUp() {
        registry = new SimpleMeterRegistry();
        Metrics.addRegistry(registry);
    }

    @AfterEach
    void tearDown() {
        Metrics.removeRegistry(registry);
        registry.close();
    }

    @Test
    @DisplayName("createOrder incrementa ordermanager.orders.placed")
    void shouldCountCreatedOrders() {
        when(repository.save(any(Order.class))).thenAnswer(i -> i.getArgument(0));
        CreateOrderRequest req = new CreateOrderRequest();
        req.setCustomerName("Metricas");

        service.createOrder(req);
        service.createOrder(req);

        // DEMO: se espera 3 a propósito (se crean 2) para mostrar que el pipeline se detiene
        assertEquals(2.0, registry.get("ordermanager.orders.placed").counter().count());
    }

    @Test
    @DisplayName("confirmOrder registra el cambio de estado con la etiqueta to=CONFIRMED")
    void shouldCountStatusChanges() {
        Order order = new Order("Metricas");
        order.setId(1L);
        when(repository.findById(1L)).thenReturn(Optional.of(order));
        when(repository.save(any(Order.class))).thenAnswer(i -> i.getArgument(0));

        service.confirmOrder(1L);

        assertEquals(1.0, registry.get("ordermanager.orders.status.changes")
                .tag("to", "CONFIRMED").counter().count());
    }
}