# PlaybackServiceChannel calls these by reflection.
-keepclassmembers class com.ryanheise.audioservice.AudioService {
    static com.ryanheise.audioservice.AudioService instance;
    private void exitForegroundState();
}
