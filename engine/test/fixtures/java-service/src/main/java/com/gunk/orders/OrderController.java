package com.gunk.orders;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RestController;
@RestController
class OrderController { private final OrderService service = new OrderService(new OrderRepository()); @PostMapping("/orders") OrderReceipt create(OrderRequest request) { return service.createOrder(request); } }
