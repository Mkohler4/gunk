package com.gunk.fixture.features.payments

class CheckoutViewModel(private val repository: PaymentsRepository) { fun createCheckout(planId: String): CheckoutSession = repository.createCheckout(planId) }
