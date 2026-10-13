package com.example.ordermanager.exception;

/**
 * Excepción lanzada cuando se intenta una transición de estado inválida.
 */
public class InvalidOrderStateException extends RuntimeException {

    public InvalidOrderStateException(String message) {
        super(message);
    }

    /**
     * Constructor de conveniencia para transiciones fallidas.
     */
    public InvalidOrderStateException(String currentState, String targetState) {
        super(String.format(
                "No se puede pasar de estado %s a %s",
                currentState, targetState
        ));
    }
}
