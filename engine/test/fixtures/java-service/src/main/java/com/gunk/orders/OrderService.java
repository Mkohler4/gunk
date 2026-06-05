package com.gunk.orders;
class OrderService { private final OrderRepository repository; OrderService(OrderRepository repository) { this.repository = repository; } OrderReceipt createOrder(OrderRequest request) { return repository.save(request); } }
