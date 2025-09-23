package com.example.trade_app_new_clean

import android.app.*
import android.content.Intent
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import android.content.Context
import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.PowerManager
import android.os.PowerManager.WakeLock
import android.graphics.Color
import android.graphics.drawable.Icon
import java.util.concurrent.Executors
import java.util.concurrent.ScheduledExecutorService
import java.util.concurrent.TimeUnit

class AutoTradingService : Service() {
    
    companion object {
        private const val NOTIFICATION_ID = 1001
        private const val CHANNEL_ID = "auto_trading_channel"
        private const val WAKE_LOCK_TAG = "AutoTradingService::WakeLock"
    }
    
    private lateinit var wakeLock: WakeLock
    private lateinit var scheduler: ScheduledExecutorService
    private var isRunning = false
    private var checkCount = 0
    
    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        acquireWakeLock()
        scheduler = Executors.newScheduledThreadPool(1)
    }
    
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            "START_FOREGROUND" -> startForegroundService()
            "STOP_FOREGROUND" -> stopForegroundService()
        }
        return START_STICKY // 서비스가 죽어도 다시 시작
    }
    
    override fun onBind(intent: Intent?): IBinder? = null
    
    private fun startForegroundService() {
        if (isRunning) return
        
        isRunning = true
        checkCount = 0
        
        // Foreground Service 시작
        val notification = createNotification()
        startForeground(NOTIFICATION_ID, notification)
        
        // 3분마다 자동매매 체크 스케줄링 (더 빠른 시그널 감지)
        scheduler.scheduleAtFixedRate({
            executeAutoTrading()
        }, 0, 3, TimeUnit.MINUTES)
        
        // 앱 아이콘에 Badge 표시
        updateAppIconBadge(true)
        
        println("🤖 자동매매 Foreground Service 시작됨")
    }
    
    private fun stopForegroundService() {
        if (!isRunning) return
        
        isRunning = false
        
        // 스케줄러 중지
        scheduler.shutdown()
        
        // Foreground Service 중지
        stopForeground(true)
        stopSelf()
        
        // 앱 아이콘 Badge 제거
        updateAppIconBadge(false)
        
        println("🛑 자동매매 Foreground Service 중지됨")
    }
    
    private fun executeAutoTrading() {
        try {
            checkCount++
            println("📊 자동매매 체크 실행 중... (${checkCount}회)")
            
            // Flutter로 자동매매 실행 이벤트 전송
            sendTradingEventToFlutter("execute_trading", checkCount)
            
            // 알림 업데이트
            updateNotification("자동매매 체크 완료 (${checkCount}회) - ${System.currentTimeMillis()}")
            
            // 앱 아이콘 Badge 업데이트 (체크 횟수 표시)
            updateAppIconBadge(true, checkCount)
            
        } catch (e: Exception) {
            println("❌ 자동매매 체크 실패: ${e.message}")
            updateNotification("자동매매 체크 실패: ${e.message}")
        }
    }
    
    private fun sendTradingEventToFlutter(action: String, checkCount: Int) {
        try {
            // MainActivity의 EventSink를 통해 Flutter로 이벤트 전송
            val eventData = mapOf(
                "action" to action,
                "checkCount" to checkCount,
                "timestamp" to System.currentTimeMillis()
            )
            
            // MainActivity의 EventSink에 접근하여 이벤트 전송
            val mainActivity = getMainActivity()
            mainActivity?.sendTradingEvent(eventData)
            
            println("📨 Flutter로 자동매매 이벤트 전송: $eventData")
        } catch (e: Exception) {
            println("❌ Flutter 이벤트 전송 실패: ${e.message}")
        }
    }
    
    private fun getMainActivity(): MainActivity? {
        return try {
            val activityManager = getSystemService(ACTIVITY_SERVICE) as android.app.ActivityManager
            val tasks = activityManager.getRunningTasks(1)
            if (tasks.isNotEmpty()) {
                val topActivity = tasks[0].topActivity
                if (topActivity?.className == "com.example.trade_app_new_clean.MainActivity") {
                    topActivity as? MainActivity
                } else {
                    null
                }
            } else {
                null
            }
        } catch (e: Exception) {
            println("❌ MainActivity 접근 실패: ${e.message}")
            null
        }
    }
    
    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                getString(R.string.auto_trading_channel_name),
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = getString(R.string.auto_trading_channel_description)
                setShowBadge(true)
                enableLights(true)
                lightColor = Color.BLUE
                enableVibration(false)
                setSound(null, null)
                lockscreenVisibility = Notification.VISIBILITY_PUBLIC
            }
            
            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            notificationManager.createNotificationChannel(channel)
        }
    }
    
    private fun createNotification(): Notification {
        val intent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK
        }
        
        val pendingIntent = PendingIntent.getActivity(
            this, 0, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        
        val notificationBuilder = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(getString(R.string.auto_trading_notification_title))
            .setContentText(getString(R.string.auto_trading_notification_content))
            .setSmallIcon(R.drawable.ic_launcher_foreground)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .setAutoCancel(false)
            .setNumber(checkCount)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
        
        // Android 14+ 호환성을 위한 추가 설정
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            notificationBuilder
                .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
        }
        
        return notificationBuilder.build()
    }
    
    private fun updateNotification(message: String) {
        val notificationBuilder = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(getString(R.string.auto_trading_notification_title))
            .setContentText(message)
            .setSmallIcon(R.drawable.ic_launcher_foreground)
            .setOngoing(true)
            .setAutoCancel(false)
            .setNumber(checkCount)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
        
        // Android 14+ 호환성을 위한 추가 설정
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            notificationBuilder
                .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
        }
        
        val notification = notificationBuilder.build()
        val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        notificationManager.notify(NOTIFICATION_ID, notification)
    }
    
    private fun updateAppIconBadge(show: Boolean, count: Int = 0) {
        try {
            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            
            if (show) {
                // Badge 표시 (체크 횟수 또는 기본값)
                val badgeCount = if (count > 0) count else 1
                
                // Android 8.0+ 에서는 채널의 Badge 설정으로 표시
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    val channel = notificationManager.getNotificationChannel(CHANNEL_ID)
                    channel?.setShowBadge(true)
                }
                
                // 알림 업데이트로 Badge 표시
                val notification = createNotification()
                notificationManager.notify(NOTIFICATION_ID, notification)
                
                println("🔴 앱 아이콘 Badge 표시: $badgeCount")
            } else {
                // Badge 제거
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    val channel = notificationManager.getNotificationChannel(CHANNEL_ID)
                    channel?.setShowBadge(false)
                }
                
                // 알림 제거
                notificationManager.cancel(NOTIFICATION_ID)
                
                println("🔴 앱 아이콘 Badge 제거")
            }
        } catch (e: Exception) {
            println("❌ 앱 아이콘 Badge 업데이트 실패: ${e.message}")
        }
    }
    
    private fun acquireWakeLock() {
        val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
        wakeLock = powerManager.newWakeLock(
            PowerManager.PARTIAL_WAKE_LOCK,
            WAKE_LOCK_TAG
        )
        wakeLock.acquire(10*60*1000L) // 10분 후 자동 해제
    }
    
    private fun releaseWakeLock() {
        if (::wakeLock.isInitialized && wakeLock.isHeld) {
            wakeLock.release()
        }
    }
    
    override fun onDestroy() {
        super.onDestroy()
        releaseWakeLock()
        if (::scheduler.isInitialized) {
            scheduler.shutdown()
        }
        // Badge 제거
        updateAppIconBadge(false)
        println("🗑️ 자동매매 서비스 정리 완료")
    }
}
