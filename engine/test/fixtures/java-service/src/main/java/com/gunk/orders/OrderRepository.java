package com.gunk.orders;
class OrderRepository { OrderReceipt save(OrderRequest request) { return new OrderReceipt(request.sku(), 1); } }
