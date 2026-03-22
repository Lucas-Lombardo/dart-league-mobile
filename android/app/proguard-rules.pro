# Stripe push provisioning (optional feature - suppress missing class warnings)
-dontwarn com.stripe.android.pushProvisioning.PushProvisioningActivity$g
-dontwarn com.stripe.android.pushProvisioning.PushProvisioningActivityStarter$Args
-dontwarn com.stripe.android.pushProvisioning.PushProvisioningActivityStarter$Error
-dontwarn com.stripe.android.pushProvisioning.PushProvisioningActivityStarter
-dontwarn com.stripe.android.pushProvisioning.PushProvisioningEphemeralKeyProvider

# TensorFlow Lite GPU delegate (optional feature)
-dontwarn org.tensorflow.lite.gpu.GpuDelegateFactory$Options

# Agora RTC Engine — uses reflection for native bridge
-keep class io.agora.** { *; }
-dontwarn io.agora.**

# Socket.IO client — uses reflection for event handling
-keep class io.socket.** { *; }
-dontwarn io.socket.**

# Flutter plugin classes
-keep class io.flutter.** { *; }
-dontwarn io.flutter.**

# Keep model/serialization classes used via reflection
-keep class com.google.gson.** { *; }
-keepattributes *Annotation*
-keepattributes Signature
