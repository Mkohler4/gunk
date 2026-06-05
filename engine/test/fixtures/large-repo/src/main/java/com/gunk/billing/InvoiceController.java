package com.gunk.billing;
class InvoiceController { private final InvoiceService service = new InvoiceService(new TaxCalculator()); Invoice create(String accountId) { return service.create(accountId); } }
