package com.gunk.fixture.features.location

import com.google.android.gms.location.FusedLocationProviderClient

class LocationRepository { fun subscribe(userId: String): LocationSubscription = LocationSubscription(userId, true) }
class LocationSubscription(val userId: String, val active: Boolean)
