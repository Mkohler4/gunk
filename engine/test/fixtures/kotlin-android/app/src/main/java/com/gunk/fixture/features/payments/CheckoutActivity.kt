package com.gunk.fixture.features.payments

class CheckoutActivity { private val viewModel = CheckoutViewModel(PaymentsRepository()); fun startCheckout(planId: String) = viewModel.createCheckout(planId) }
