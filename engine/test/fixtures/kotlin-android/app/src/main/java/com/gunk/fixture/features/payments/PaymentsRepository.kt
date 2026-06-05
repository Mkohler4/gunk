package com.gunk.fixture.features.payments

import com.android.billingclient.api.BillingClient

class PaymentsRepository { fun createCheckout(planId: String): CheckoutSession { return CheckoutSession(planId, "billing-client-token") } }
class CheckoutSession(val planId: String, val token: String)
