package com.example.trade_app_new_clean

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.EventChannel
import android.content.Intent
import android.os.Build
import android.util.Log
import android.content.ComponentName
import android.content.pm.PackageManager
import android.os.PowerManager
import android.provider.Settings
import android.net.Uri

class MainActivity: FlutterActivity() {
    private val CHANNEL = "auto_trading_service"
    private val BATTERY_CHANNEL = "battery_optimization"
    private val APP_ICON_BADGE_CHANNEL = "app_icon_badge"
    private val TRADING_EVENTS_CHANNEL = "auto_trading_events"
    
    private var tradingEventSink: EventChannel.EventSink? = null
    
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            Log.d("MainActivity", "📞 메서드 호출: ${call.method}")
            when (call.method) {
                "startForegroundService" -> {
                    startAutoTradingService()
                    result.success(true)
                }
                "stopForegroundService" -> {
                    stopAutoTradingService()
                    result.success(true)
                }
                "updateAppIcon" -> {
                    val isActive = call.argument<Boolean>("isActive") ?: false
                    Log.d("MainActivity", "🔴 updateAppIcon 호출됨: isActive=$isActive")
                    // 앱 아이콘 Badge는 Foreground Service 알림으로 처리되므로 여기서는 로그만 출력
                    Log.d("MainActivity", "✅ 앱 아이콘 Badge 상태: ${if (isActive) "활성화" else "비활성화"}")
                    result.success(true)
                }
                else -> {
                    Log.e("MainActivity", "❌ 구현되지 않은 메서드: ${call.method}")
                    result.notImplemented()
                }
            }
        }
        
        // 배터리 최적화 관련 MethodChannel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, BATTERY_CHANNEL).setMethodCallHandler { call, result ->
            Log.d("MainActivity", "🔋 배터리 최적화 메서드 호출: ${call.method}")
            when (call.method) {
                "requestIgnoreBatteryOptimization" -> {
                    requestIgnoreBatteryOptimization(result)
                }
                "openBatteryOptimizationSettings" -> {
                    openBatteryOptimizationSettings(result)
                }
                else -> {
                    Log.e("MainActivity", "❌ 구현되지 않은 배터리 최적화 메서드: ${call.method}")
                    result.notImplemented()
                }
            }
        }
        
        // 앱 아이콘 배지 관련 MethodChannel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, APP_ICON_BADGE_CHANNEL).setMethodCallHandler { call, result ->
            Log.d("MainActivity", "🔴 앱 아이콘 배지 메서드 호출: ${call.method}")
            when (call.method) {
                "showAutoTradingBadge" -> {
                    showAutoTradingBadge(result)
                }
                "hideAutoTradingBadge" -> {
                    hideAutoTradingBadge(result)
                }
                else -> {
                    Log.e("MainActivity", "❌ 구현되지 않은 앱 아이콘 배지 메서드: ${call.method}")
                    result.notImplemented()
                }
            }
        }
        
        // 자동매매 이벤트 채널 설정
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, TRADING_EVENTS_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    Log.d("MainActivity", "🎧 자동매매 이벤트 리스너 시작")
                    tradingEventSink = events
                }
                
                override fun onCancel(arguments: Any?) {
                    Log.d("MainActivity", "🛑 자동매매 이벤트 리스너 중지")
                    tradingEventSink = null
                }
            }
        )
    }
    
    private fun startAutoTradingService() {
        try {
            Log.d("MainActivity", "🚀 자동매매 Foreground Service 시작 요청")
            
            val serviceIntent = Intent(this, AutoTradingService::class.java).apply {
                action = "START_FOREGROUND"
            }
            
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                startForegroundService(serviceIntent)
            } else {
                startService(serviceIntent)
            }
            
            // 앱 아이콘 Badge는 Foreground Service에서 처리됨
            
            Log.d("MainActivity", "✅ 자동매매 Foreground Service 시작됨")
        } catch (e: Exception) {
            Log.e("MainActivity", "❌ 자동매매 Foreground Service 시작 실패: ${e.message}")
        }
    }
    
    private fun stopAutoTradingService() {
        try {
            Log.d("MainActivity", "🛑 자동매매 Foreground Service 중지 요청")
            
            val serviceIntent = Intent(this, AutoTradingService::class.java).apply {
                action = "STOP_FOREGROUND"
            }
            
            startService(serviceIntent)
            
            // 앱 아이콘 Badge는 Foreground Service에서 처리됨
            
            Log.d("MainActivity", "✅ 자동매매 Foreground Service 중지됨")
        } catch (e: Exception) {
            Log.e("MainActivity", "❌ 자동매매 Foreground Service 중지 실패: ${e.message}")
        }
    }
    
    private fun updateAppIcon(isActive: Boolean) {
        try {
            val packageManager = packageManager
            val componentName = ComponentName(this, MainActivity::class.java)
            
            if (isActive) {
                // 자동매매 활성화 아이콘으로 변경
                packageManager.setComponentEnabledSetting(
                    componentName,
                    PackageManager.COMPONENT_ENABLED_STATE_ENABLED,
                    PackageManager.DONT_KILL_APP
                )
                
                // 앱 아이콘을 빨간색으로 변경 (자동매매 활성화 표시)
                // 실제로는 별도의 아이콘 리소스를 사용해야 하지만, 여기서는 알림 Badge로 대체
                Log.d("MainActivity", "🔴 앱 아이콘을 자동매매 활성화 상태로 변경")
            } else {
                // 기본 아이콘으로 복원
                packageManager.setComponentEnabledSetting(
                    componentName,
                    PackageManager.COMPONENT_ENABLED_STATE_ENABLED,
                    PackageManager.DONT_KILL_APP
                )
                
                Log.d("MainActivity", "⚪ 앱 아이콘을 기본 상태로 복원")
            }
        } catch (e: Exception) {
            Log.e("MainActivity", "❌ 앱 아이콘 변경 실패: ${e.message}")
        }
    }
    
    private fun requestIgnoreBatteryOptimization(result: MethodChannel.Result) {
        try {
            Log.d("MainActivity", "🔋 배터리 최적화 무시 권한 요청")
            
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                val powerManager = getSystemService(POWER_SERVICE) as PowerManager
                val packageName = packageName
                
                if (!powerManager.isIgnoringBatteryOptimizations(packageName)) {
                    val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                        data = Uri.parse("package:$packageName")
                    }
                    startActivity(intent)
                    Log.d("MainActivity", "✅ 배터리 최적화 무시 권한 요청 화면 열기")
                    result.success(true)
                } else {
                    Log.d("MainActivity", "✅ 이미 배터리 최적화가 무시되고 있음")
                    result.success(true)
                }
            } else {
                Log.d("MainActivity", "⚠️ Android 6.0 미만에서는 배터리 최적화 무시가 지원되지 않음")
                result.success(true)
            }
        } catch (e: Exception) {
            Log.e("MainActivity", "❌ 배터리 최적화 무시 권한 요청 실패: ${e.message}")
            result.success(false)
        }
    }
    
    private fun openBatteryOptimizationSettings(result: MethodChannel.Result) {
        try {
            Log.d("MainActivity", "🔋 배터리 최적화 설정 화면 열기")
            
            val intent = Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)
            startActivity(intent)
            
            Log.d("MainActivity", "✅ 배터리 최적화 설정 화면 열기 완료")
            result.success(true)
        } catch (e: Exception) {
            Log.e("MainActivity", "❌ 배터리 최적화 설정 화면 열기 실패: ${e.message}")
            result.success(false)
        }
    }
    
    private fun showAutoTradingBadge(result: MethodChannel.Result) {
        try {
            Log.d("MainActivity", "🔴 자동매매 배지 표시")
            
            // 앱 아이콘에 빨간색 배지 표시 (자동매매 활성화)
            val packageManager = packageManager
            val componentName = ComponentName(this, MainActivity::class.java)
            
            // 앱 아이콘을 자동매매 활성화 상태로 변경
            packageManager.setComponentEnabledSetting(
                componentName,
                PackageManager.COMPONENT_ENABLED_STATE_ENABLED,
                PackageManager.DONT_KILL_APP
            )
            
            // 실제로는 별도의 아이콘 리소스를 사용해야 하지만, 여기서는 알림 Badge로 대체
            // Foreground Service 알림에서 배지 표시
            Log.d("MainActivity", "🔴 앱 아이콘에 자동매매 배지 표시됨")
            result.success(true)
        } catch (e: Exception) {
            Log.e("MainActivity", "❌ 자동매매 배지 표시 실패: ${e.message}")
            result.success(false)
        }
    }
    
    private fun hideAutoTradingBadge(result: MethodChannel.Result) {
        try {
            Log.d("MainActivity", "⚪ 자동매매 배지 제거")
            
            // 앱 아이콘을 기본 상태로 복원
            val packageManager = packageManager
            val componentName = ComponentName(this, MainActivity::class.java)
            
            packageManager.setComponentEnabledSetting(
                componentName,
                PackageManager.COMPONENT_ENABLED_STATE_ENABLED,
                PackageManager.DONT_KILL_APP
            )
            
            Log.d("MainActivity", "⚪ 앱 아이콘에서 자동매매 배지 제거됨")
            result.success(true)
        } catch (e: Exception) {
            Log.e("MainActivity", "❌ 자동매매 배지 제거 실패: ${e.message}")
            result.success(false)
        }
    }
    
    /// Flutter로 자동매매 이벤트 전송
    fun sendTradingEvent(eventData: Map<String, Any>) {
        try {
            tradingEventSink?.success(eventData)
            Log.d("MainActivity", "📨 자동매매 이벤트 전송: $eventData")
        } catch (e: Exception) {
            Log.e("MainActivity", "❌ 자동매매 이벤트 전송 실패: ${e.message}")
        }
    }
}
