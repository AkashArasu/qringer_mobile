package io.getstream.video.flutter.stream_video_push_notification

import android.content.Context
import android.util.Log
import androidx.work.Constraints
import androidx.work.CoroutineWorker
import androidx.work.ExistingWorkPolicy
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkerParameters
import androidx.work.WorkManager
import androidx.work.Data as WorkData
import com.google.android.gms.tasks.Tasks
import com.google.firebase.auth.FirebaseAuth
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.TimeUnit

/** Delivers notification Reject even when no Flutter event listener is alive. */
class QROnlyRejectWorker(context: Context, params: WorkerParameters) :
    CoroutineWorker(context, params) {

    companion object {
        private const val TAG = "QROnlyReject"
        private val callCidPattern = Regex("^default:([a-f0-9]{32})$")
        private val propertyIdPattern = Regex("^[a-f0-9]{20}$")

        fun enqueue(context: Context, call: Data) {
            val extra = call.extra
            val callId = callCidPattern.matchEntire(extra["callCid"] as? String ?: "")?.groupValues?.get(1)
            val propertyId = extra["propertyId"] as? String
            val baseUrl = extra["signalingBaseUrl"] as? String
            if (callId == null || propertyId == null || !propertyIdPattern.matches(propertyId) ||
                baseUrl.isNullOrBlank() || !baseUrl.startsWith("https://")) {
                Log.e(TAG, "Cannot signal Reject: notification lacks validated call metadata")
                return
            }
            val input = WorkData.Builder()
                .putString("callId", callId)
                .putString("propertyId", propertyId)
                .putString("baseUrl", baseUrl.trimEnd('/'))
                .build()
            val work = OneTimeWorkRequestBuilder<QROnlyRejectWorker>()
                .setInputData(input)
                .setConstraints(Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build())
                .build()
            WorkManager.getInstance(context).enqueueUniqueWork(
                "qronly-reject-$callId", ExistingWorkPolicy.KEEP, work
            )
            Log.i(TAG, "Queued native Reject for call=$callId")
        }
    }

    override suspend fun doWork(): Result {
        if (runAttemptCount >= 4) return Result.failure()
        val callId = inputData.getString("callId") ?: return Result.failure()
        val propertyId = inputData.getString("propertyId") ?: return Result.failure()
        val baseUrl = inputData.getString("baseUrl") ?: return Result.failure()
        if (!callCidPattern.matches("default:$callId") || !propertyIdPattern.matches(propertyId) ||
            !baseUrl.startsWith("https://")) return Result.failure()
        try {
            val user = FirebaseAuth.getInstance().currentUser ?: return Result.failure()
            val token = Tasks.await(user.getIdToken(runAttemptCount > 0), 8, TimeUnit.SECONDS).token
                ?: return Result.retry()
            val url = URL("$baseUrl/v1/calls/$callId/reject")
            if (url.protocol != "https") return Result.failure()
            val connection = url.openConnection() as HttpURLConnection
            try {
                connection.requestMethod = "POST"
                connection.connectTimeout = 8000
                connection.readTimeout = 8000
                connection.setRequestProperty("Authorization", "Bearer $token")
                connection.setRequestProperty("X-Property-Id", propertyId)
                connection.setRequestProperty("Content-Type", "application/json")
                connection.doOutput = true
                connection.outputStream.use { it.write("{}".toByteArray(Charsets.UTF_8)) }
                val code = connection.responseCode
                Log.i(TAG, "Native Reject result=$code call=$callId")
                return when {
                    code in 200..299 || code == 404 || code == 409 -> Result.success()
                    code == 401 || code == 408 || code == 429 || code >= 500 -> Result.retry()
                    else -> Result.failure()
                }
            } finally {
                connection.disconnect()
            }
        } catch (error: Exception) {
            Log.w(TAG, "Native Reject delivery failed; retrying call=$callId", error)
            return Result.retry()
        }
    }
}
