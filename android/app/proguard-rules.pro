# WebRTC sınıfları yansıma ile çağrılır; küçültmede silinmesin.
-keep class org.webrtc.** { *; }
-keep class com.cloudwebrtc.webrtc.** { *; }
-dontwarn org.webrtc.**
