package com.github.blueboytm.flutter_v2ray.v2ray.core;

import static com.github.blueboytm.flutter_v2ray.v2ray.utils.Utilities.getUserAssetsPath;

import android.Manifest;
import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.app.Service;
import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.graphics.Color;
import android.os.Build;
import android.os.CountDownTimer;
import android.util.Log;

import androidx.annotation.RequiresApi;
import androidx.core.app.ActivityCompat;
import androidx.core.app.NotificationCompat;

import com.github.blueboytm.flutter_v2ray.v2ray.interfaces.V2rayServicesListener;
import com.github.blueboytm.flutter_v2ray.v2ray.services.V2rayProxyOnlyService;
import com.github.blueboytm.flutter_v2ray.v2ray.services.V2rayVPNService;
import com.github.blueboytm.flutter_v2ray.v2ray.utils.AppConfigs;
import com.github.blueboytm.flutter_v2ray.v2ray.utils.Utilities;
import com.github.blueboytm.flutter_v2ray.v2ray.utils.V2rayConfig;

import org.json.JSONObject;

import go.Seq;
import libv2ray.CoreCallbackHandler;
import libv2ray.CoreController;
import libv2ray.Libv2ray;

/**
 * Compatibility adapter for the maintained AndroidLibXrayLite binding.
 *
 * flutter_v2ray originally used the retired V2RayPoint API. Current Xray
 * Android bindings expose CoreController. This adapter preserves the plugin's
 * existing Flutter service/broadcast contract while upgrading the core that
 * parses VLESS Encryption and current REALITY settings.
 */
public final class V2rayCoreManager {
    private static final int NOTIFICATION_ID = 1;
    private volatile static V2rayCoreManager INSTANCE;

    public V2rayServicesListener v2rayServicesListener = null;
    public AppConfigs.V2RAY_STATES V2RAY_STATE = AppConfigs.V2RAY_STATES.V2RAY_DISCONNECTED;

    private CoreController coreController;
    private boolean isLibV2rayCoreInitialized = false;
    private CountDownTimer countDownTimer;
    private int seconds;
    private int minutes;
    private int hours;
    private long totalDownload;
    private long totalUpload;
    private long uploadSpeed;
    private long downloadSpeed;
    private String serviceDuration = "00:00:00";

    private final CoreCallbackHandler coreCallbackHandler = new CoreCallbackHandler() {
        @Override
        public long startup() {
            return 0;
        }

        @Override
        public long shutdown() {
            sendDisconnectedBroadcast();
            return 0;
        }

        @Override
        public long onEmitStatus(long code, String message) {
            if (message != null && !message.trim().isEmpty()) {
                Log.i(V2rayCoreManager.class.getSimpleName(), "Xray status " + code + ": " + message);
            }
            return 0;
        }
    };

    public static V2rayCoreManager getInstance() {
        if (INSTANCE == null) {
            synchronized (V2rayCoreManager.class) {
                if (INSTANCE == null) {
                    INSTANCE = new V2rayCoreManager();
                }
            }
        }
        return INSTANCE;
    }

    private void makeDurationTimer(final Context context, final boolean enableTrafficStatics) {
        if (countDownTimer != null) {
            countDownTimer.cancel();
        }
        countDownTimer = new CountDownTimer(7200, 1000) {
            @RequiresApi(api = Build.VERSION_CODES.M)
            public void onTick(long millisUntilFinished) {
                seconds++;
                if (seconds == 60) {
                    minutes++;
                    seconds = 0;
                }
                if (minutes == 60) {
                    hours++;
                    minutes = 0;
                }
                if (hours == 24) {
                    hours = 0;
                }
                if (enableTrafficStatics && coreController != null && coreController.getIsRunning()) {
                    downloadSpeed = coreController.queryStats("block", "downlink")
                            + coreController.queryStats("proxy", "downlink");
                    uploadSpeed = coreController.queryStats("block", "uplink")
                            + coreController.queryStats("proxy", "uplink");
                    totalDownload += downloadSpeed;
                    totalUpload += uploadSpeed;
                }
                serviceDuration = Utilities.convertIntToTwoDigit(hours) + ":"
                        + Utilities.convertIntToTwoDigit(minutes) + ":"
                        + Utilities.convertIntToTwoDigit(seconds);
                Intent intent = new Intent("V2RAY_CONNECTION_INFO");
                intent.putExtra("STATE", V2rayCoreManager.getInstance().V2RAY_STATE);
                intent.putExtra("DURATION", serviceDuration);
                intent.putExtra("UPLOAD_SPEED", uploadSpeed);
                intent.putExtra("DOWNLOAD_SPEED", downloadSpeed);
                intent.putExtra("UPLOAD_TRAFFIC", totalUpload);
                intent.putExtra("DOWNLOAD_TRAFFIC", totalDownload);
                context.sendBroadcast(intent);
            }

            public void onFinish() {
                if (isV2rayCoreRunning()) {
                    makeDurationTimer(context, enableTrafficStatics);
                }
            }
        }.start();
    }

    public synchronized void setUpListener(Service targetService) {
        try {
            v2rayServicesListener = (V2rayServicesListener) targetService;
            Seq.setContext(targetService.getApplicationContext());
            Libv2ray.initCoreEnv(getUserAssetsPath(targetService.getApplicationContext()), "");
            if (coreController == null) {
                coreController = Libv2ray.newCoreController(coreCallbackHandler);
            }
            isLibV2rayCoreInitialized = true;
            resetStats();
            Log.i(V2rayCoreManager.class.getSimpleName(), "Initialized maintained Xray core");
        } catch (Exception e) {
            Log.e(V2rayCoreManager.class.getSimpleName(), "setUpListener failed", e);
            isLibV2rayCoreInitialized = false;
        }
    }

    public boolean startCore(final V2rayConfig v2rayConfig) {
        return startCore(v2rayConfig, 0);
    }

    /** Starts the new Xray core; VPN mode supplies an already established TUN fd. */
    public synchronized boolean startCore(final V2rayConfig v2rayConfig, final int tunFd) {
        V2RAY_STATE = AppConfigs.V2RAY_STATES.V2RAY_CONNECTING;
        if (!isLibV2rayCoreInitialized || coreController == null || v2rayServicesListener == null) {
            Log.e(V2rayCoreManager.class.getSimpleName(), "startCore failed: core is not initialized");
            sendDisconnectedBroadcast();
            return false;
        }
        try {
            if (isV2rayCoreRunning()) {
                stopCore();
            }
            resetStats();
            coreController.startLoop(v2rayConfig.V2RAY_FULL_JSON_CONFIG, tunFd);
            if (!coreController.getIsRunning()) {
                throw new IllegalStateException("Xray core did not enter a running state");
            }
            V2RAY_STATE = AppConfigs.V2RAY_STATES.V2RAY_CONNECTED;
            makeDurationTimer(v2rayServicesListener.getService().getApplicationContext(),
                    v2rayConfig.ENABLE_TRAFFIC_STATICS);
            showNotification(v2rayConfig);
            return true;
        } catch (Exception e) {
            Log.e(V2rayCoreManager.class.getSimpleName(), "startCore failed", e);
            sendDisconnectedBroadcast();
            return false;
        }
    }

    public synchronized void stopCore() {
        try {
            if (v2rayServicesListener != null) {
                NotificationManager notificationManager = (NotificationManager) v2rayServicesListener
                        .getService().getSystemService(Context.NOTIFICATION_SERVICE);
                if (notificationManager != null) {
                    notificationManager.cancel(NOTIFICATION_ID);
                }
            }
            if (coreController != null && coreController.getIsRunning()) {
                coreController.stopLoop();
            }
        } catch (Exception e) {
            Log.e(V2rayCoreManager.class.getSimpleName(), "stopCore failed", e);
        } finally {
            sendDisconnectedBroadcast();
        }
    }

    private void resetStats() {
        serviceDuration = "00:00:00";
        seconds = 0;
        minutes = 0;
        hours = 0;
        uploadSpeed = 0;
        downloadSpeed = 0;
        totalDownload = 0;
        totalUpload = 0;
    }

    private void sendDisconnectedBroadcast() {
        V2RAY_STATE = AppConfigs.V2RAY_STATES.V2RAY_DISCONNECTED;
        resetStats();
        if (countDownTimer != null) {
            countDownTimer.cancel();
            countDownTimer = null;
        }
        if (v2rayServicesListener == null) {
            return;
        }
        try {
            Intent intent = new Intent("V2RAY_CONNECTION_INFO");
            intent.putExtra("STATE", V2RAY_STATE);
            intent.putExtra("DURATION", serviceDuration);
            intent.putExtra("UPLOAD_SPEED", uploadSpeed);
            intent.putExtra("DOWNLOAD_SPEED", downloadSpeed);
            intent.putExtra("UPLOAD_TRAFFIC", totalUpload);
            intent.putExtra("DOWNLOAD_TRAFFIC", totalDownload);
            v2rayServicesListener.getService().getApplicationContext().sendBroadcast(intent);
        } catch (Exception ignored) {
            // The service may already be shutting down.
        }
    }

    private String createNotificationChannelID(String appName) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && v2rayServicesListener != null) {
            NotificationManager manager = (NotificationManager) v2rayServicesListener.getService()
                    .getSystemService(Context.NOTIFICATION_SERVICE);
            String channelId = "A_FLUTTER_V2RAY_SERVICE_CH_ID";
            String channelName = appName + " Background Service";
            NotificationChannel channel = new NotificationChannel(channelId, channelName,
                    NotificationManager.IMPORTANCE_DEFAULT);
            channel.setDescription(channelName);
            channel.setLightColor(Color.DKGRAY);
            channel.setLockscreenVisibility(Notification.VISIBILITY_PRIVATE);
            if (manager != null) {
                manager.createNotificationChannel(channel);
            }
            return channelId;
        }
        return "";
    }

    private void showNotification(final V2rayConfig v2rayConfig) {
        if (v2rayServicesListener == null) {
            return;
        }
        Service context = v2rayServicesListener.getService();
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU
                && ActivityCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS)
                != PackageManager.PERMISSION_GRANTED) {
            return;
        }
        Intent launchIntent = context.getPackageManager().getLaunchIntentForPackage(context.getPackageName());
        if (launchIntent != null) {
            launchIntent.setAction("FROM_DISCONNECT_BTN");
            launchIntent.setFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TASK);
        }
        int flags = Build.VERSION.SDK_INT >= Build.VERSION_CODES.M
                ? PendingIntent.FLAG_IMMUTABLE | PendingIntent.FLAG_UPDATE_CURRENT
                : PendingIntent.FLAG_UPDATE_CURRENT;
        PendingIntent contentIntent = PendingIntent.getActivity(context, 0, launchIntent, flags);
        Intent stopIntent;
        if (AppConfigs.V2RAY_CONNECTION_MODE == AppConfigs.V2RAY_CONNECTION_MODES.PROXY_ONLY) {
            stopIntent = new Intent(context, V2rayProxyOnlyService.class);
        } else if (AppConfigs.V2RAY_CONNECTION_MODE == AppConfigs.V2RAY_CONNECTION_MODES.VPN_TUN) {
            stopIntent = new Intent(context, V2rayVPNService.class);
        } else {
            return;
        }
        stopIntent.putExtra("COMMAND", AppConfigs.V2RAY_SERVICE_COMMANDS.STOP_SERVICE);
        PendingIntent stopPendingIntent = PendingIntent.getService(context, 0, stopIntent, flags);
        NotificationCompat.Builder builder = new NotificationCompat.Builder(context,
                createNotificationChannelID(v2rayConfig.APPLICATION_NAME))
                .setSmallIcon(v2rayConfig.APPLICATION_ICON)
                .setContentTitle(v2rayConfig.REMARK)
                .addAction(0, v2rayConfig.NOTIFICATION_DISCONNECT_BUTTON_NAME, stopPendingIntent)
                .setPriority(NotificationCompat.PRIORITY_MIN)
                .setShowWhen(false)
                .setOnlyAlertOnce(true)
                .setContentIntent(contentIntent)
                .setOngoing(true);
        context.startForeground(NOTIFICATION_ID, builder.build());
    }

    public boolean isV2rayCoreRunning() {
        return coreController != null && coreController.getIsRunning();
    }

    public Long getConnectedV2rayServerDelay() {
        try {
            return coreController != null && coreController.getIsRunning()
                    ? coreController.measureDelay(AppConfigs.DELAY_URL)
                    : -1L;
        } catch (Exception e) {
            return -1L;
        }
    }

    public Long getV2rayServerDelay(final String config, final String url) {
        try {
            try {
                JSONObject configJson = new JSONObject(config);
                JSONObject routing = configJson.getJSONObject("routing");
                routing.remove("rules");
                configJson.remove("routing");
                configJson.put("routing", routing);
                return Libv2ray.measureOutboundDelay(configJson.toString(), url);
            } catch (Exception jsonError) {
                Log.e("getV2rayServerDelay", jsonError.toString());
                return Libv2ray.measureOutboundDelay(config, url);
            }
        } catch (Exception e) {
            Log.e("getV2rayServerDelayCore", e.toString());
            return -1L;
        }
    }
}
