package com.gunk.billing;
class InvoiceService { private final TaxCalculator taxes; InvoiceService(TaxCalculator taxes) { this.taxes = taxes; } Invoice create(String accountId) { return new Invoice(accountId, taxes.total(100)); } }
