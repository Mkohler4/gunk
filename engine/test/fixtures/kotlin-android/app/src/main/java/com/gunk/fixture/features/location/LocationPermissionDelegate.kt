package com.gunk.fixture.features.location

class LocationPermissionDelegate { fun hasPermission(grants: Set<String>) = grants.contains("android.permission.ACCESS_FINE_LOCATION") }
