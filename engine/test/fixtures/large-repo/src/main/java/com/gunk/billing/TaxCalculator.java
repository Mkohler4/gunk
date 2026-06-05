package com.gunk.billing;
class TaxCalculator { int total(int subtotal) { return subtotal + 8; } }
record Invoice(String accountId, int total) {}
