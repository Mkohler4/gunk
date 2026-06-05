package com.gunk.orders;
record OrderRequest(String sku, int quantity) {}
record OrderReceipt(String sku, int quantity) {}
