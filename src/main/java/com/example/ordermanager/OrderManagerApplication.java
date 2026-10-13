package com.example.ordermanager;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

/**
 * Punto de entrada de la aplicación Order Manager API.
 *
 * @SpringBootApplication combina:
 *   - @Configuration
 *   - @EnableAutoConfiguration
 *   - @ComponentScan
 */
@SpringBootApplication
public class OrderManagerApplication {

    public static void main(String[] args) {
        SpringApplication.run(OrderManagerApplication.class, args);
    }
}
