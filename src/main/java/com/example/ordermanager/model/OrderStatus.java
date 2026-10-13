package com.example.ordermanager.model;

/**
 * Estados posibles de un pedido.
 *
 * Flujo válido:
 *   PENDING → CONFIRMED → SHIPPED → DELIVERED
 *       ↓         ↓          ↓
 *   CANCELLED CANCELLED  CANCELLED
 *
 * Regla: DELIVERED es terminal (no se puede cancelar).
 */
public enum OrderStatus {
    PENDING,
    CONFIRMED,
    SHIPPED,
    DELIVERED,
    CANCELLED
}
