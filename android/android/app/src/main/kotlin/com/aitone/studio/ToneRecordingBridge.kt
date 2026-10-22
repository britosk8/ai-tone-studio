package com.aitone.studio

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.pm.PackageManager
import android.media.*
import android.media.audiofx.*
import io.flutter.plugin.common.*
import java.io.File
import java.io.RandomAccessFile
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.concurrent.Executors

/** Captura áudio em primeiro plano. Nunca altera globals ou firmware da pedaleira. */
class ToneRecordingBridge(private val activity: Activity, messenger: BinaryMessenger) : MethodChannel.MethodCallHandler {
    private val manager=activity.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    private val worker=Executors.newSingleThreadExecutor()
    private var recorder: AudioRecord?=null
    @Volatile private var active=false
    @Volatile private var finished=false
    @Volatile private var lastError: String?=null
    private var file:File?=null
    private var inputName=""
    private val effects=mutableListOf<AudioEffect>()
    init {MethodChannel(messenger,"ai_tone/recording").setMethodCallHandler(this)}
    private fun usb(d:AudioDeviceInfo)=d.type==AudioDeviceInfo.TYPE_USB_DEVICE || d.type==AudioDeviceInfo.TYPE_USB_HEADSET
    override fun onMethodCall(call:MethodCall,result:MethodChannel.Result) {
        try {
            when(call.method) {
                "inputs" -> result.success(manager.getDevices(AudioManager.GET_DEVICES_INPUTS).filter{usb(it)||it.type==AudioDeviceInfo.TYPE_BUILTIN_MIC}.map{mapOf("id" to it.id,"name" to it.productName.toString(),"kind" to if(usb(it))"usb" else "microphone")})
                "start" -> {
                    if(active || recorder!=null)throw IllegalStateException("Gravação já em andamento")
                    if(activity.checkSelfPermission(Manifest.permission.RECORD_AUDIO)!=PackageManager.PERMISSION_GRANTED)throw IllegalStateException("Autorize a gravação de áudio no Android")
                    val kind=call.argument<String>("kind") ?: "usb"
                    val id=call.argument<Int>("id")
                    val seconds=(call.argument<Int>("seconds") ?: 10).coerceIn(3,30)
                    val available=manager.getDevices(AudioManager.GET_DEVICES_INPUTS)
                    val device=available.firstOrNull{(id==null || it.id==id) && if(kind=="usb")usb(it)else it.type==AudioDeviceInfo.TYPE_BUILTIN_MIC}
                        ?: throw IllegalStateException(if(kind=="usb")"Nenhuma entrada USB de áudio encontrada. Confira OTG e o modo de áudio processado no pedal." else "Microfone indisponível")
                    val sr=if(device.sampleRates.contains(44100)||device.sampleRates.isEmpty())44100 else if(device.sampleRates.contains(48000))48000 else throw IllegalStateException("Entrada não suporta 44.1/48 kHz")
                    val channels=if(kind=="usb" && device.channelCounts.contains(2))2 else 1
                    val format=AudioFormat.Builder().setSampleRate(sr).setEncoding(AudioFormat.ENCODING_PCM_16BIT).setChannelMask(if(channels==2)AudioFormat.CHANNEL_IN_STEREO else AudioFormat.CHANNEL_IN_MONO).build()
                    val buffer=AudioRecord.getMinBufferSize(sr,format.channelMask,AudioFormat.ENCODING_PCM_16BIT).coerceAtLeast(sr*channels/5)
                    val audio=AudioRecord.Builder().setAudioSource(MediaRecorder.AudioSource.VOICE_RECOGNITION).setAudioFormat(format).setBufferSizeInBytes(buffer*2).build()
                    if(audio.state!=AudioRecord.STATE_INITIALIZED || !audio.setPreferredDevice(device)){audio.release();throw IllegalStateException("Não foi possível selecionar essa entrada de áudio")}
                    recorder=audio
                    try {
                        if(AutomaticGainControl.isAvailable())AutomaticGainControl.create(audio.audioSessionId)?.let{it.enabled=false;effects.add(it)}
                        if(NoiseSuppressor.isAvailable())NoiseSuppressor.create(audio.audioSessionId)?.let{it.enabled=false;effects.add(it)}
                        if(AcousticEchoCanceler.isAvailable())AcousticEchoCanceler.create(audio.audioSessionId)?.let{it.enabled=false;effects.add(it)}
                        file?.delete();file=File(activity.cacheDir,"tone-recording-${System.nanoTime()}.wav")
                        inputName=device.productName.toString();finished=false;lastError=null;active=true
                        audio.startRecording()
                        worker.execute {
                            try {
                                RandomAccessFile(file!!,"rw").use{out ->
                                    out.write(ByteArray(44))
                                    val bytes=ByteArray(buffer);var total=0;var checked=false
                                    val limit=sr*channels*2*seconds
                                    while(active && total<limit) {
                                        val count=audio.read(bytes,0,minOf(bytes.size,limit-total),AudioRecord.READ_BLOCKING)
                                        if(count<=0)throw IllegalStateException("A entrada de áudio foi interrompida ($count)")
                                        val routed=audio.routedDevice
                                        if(!checked && total>=sr*channels*2/2) {
                                            if(routed==null || routed.id!=device.id)throw IllegalStateException("Android não roteou a gravação para a entrada escolhida. Nenhum microfone alternativo foi usado.")
                                            checked=true
                                        }
                                        if(checked && (routed==null || routed.id!=device.id))throw IllegalStateException("Entrada selecionada desconectada durante a gravação")
                                        out.write(bytes,0,count);total+=count
                                    }
                                    if(!checked)throw IllegalStateException("Gravação muito curta para confirmar a entrada")
                                    out.seek(0);out.write(header(total,sr,channels))
                                }
                            } catch(e:Exception){lastError=e.message ?: "Falha na captura";file?.delete()}
                            finally {
                                active=false
                                try{audio.stop()}catch(_:Exception){}
                                effects.forEach{it.release()};effects.clear();audio.release();recorder=null;finished=true
                            }
                        }
                        result.success(mapOf("input" to inputName,"seconds" to seconds,"sample_rate" to sr,"channels" to channels))
                    }catch(e:Exception){active=false;effects.forEach{it.release()};effects.clear();audio.release();recorder=null;throw e}
                }
                "status" -> result.success(mapOf("recording" to active,"finished" to finished,"error" to lastError,"path" to if(finished && lastError==null)file?.absolutePath else null,"input" to inputName))
                "stop" -> {
                    active=false
                    worker.execute{activity.runOnUiThread{if(lastError!=null)result.error("recording_error",lastError,null)else if(file?.exists()==true)result.success(file!!.absolutePath)else result.error("recording_error","Nenhum áudio gravado",null)}}
                }
                "cancel" -> {active=false;worker.execute{file?.delete();file=null;finished=false};result.success(null)}
                else -> result.notImplemented()
            }
        }catch(e:Exception){result.error("recording_error",e.message,null)}
    }
    private fun header(size:Int,sr:Int,channels:Int):ByteArray {
        val b=ByteBuffer.allocate(44).order(ByteOrder.LITTLE_ENDIAN)
        b.put("RIFF".toByteArray()).putInt(size+36).put("WAVEfmt ".toByteArray()).putInt(16).putShort(1.toShort()).putShort(channels.toShort())
        b.putInt(sr).putInt(sr*channels*2).putShort((channels*2).toShort()).putShort(16.toShort()).put("data".toByteArray()).putInt(size)
        return b.array()
    }
    fun dispose(){active=false;worker.execute{file?.delete()};worker.shutdown()}
}
