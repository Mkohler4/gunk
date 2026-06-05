package com.gunk.fixture.features.location

class LocationTracker(private val repository: LocationRepository) { fun beginTracking(userId: String) = repository.subscribe(userId) }
