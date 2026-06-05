plugins { id("com.android.application"); id("org.jetbrains.kotlin.android") }

android { namespace = "com.gunk.fixture"; compileSdk = 35 }

dependencies {
  implementation("com.squareup.retrofit2:retrofit:2.11.0")
  implementation("com.android.billingclient:billing-ktx:7.0.0")
  implementation("com.google.android.gms:play-services-location:21.3.0")
}
