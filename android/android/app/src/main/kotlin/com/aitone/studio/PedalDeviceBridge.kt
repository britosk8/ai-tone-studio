package com.aitone.studio

import android.Manifest
import android.app.Activity
import android.bluetooth.*
import android.bluetooth.le.*
import android.content.Context
import android.content.pm.PackageManager
import android.media.midi.*
import android.os.*
import io.flutter.plugin.common.*
import java.util.UUID

/** USB MIDI nativo e GATT M-EFCS. Não decide modelos, endereços ou gravações. */
class PedalDeviceBridge(private val activity: Activity, messenger: BinaryMessenger) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler {
    private val main = Handler(Looper.getMainLooper())
    private val midi = activity.getSystemService(Context.MIDI_SERVICE) as? MidiManager
    private val bluetooth = activity.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager
    private var sink: EventChannel.EventSink? = null
    private var midiDevice: MidiDevice? = null
    private var input: MidiInputPort? = null
    private var output: MidiOutputPort? = null
    private var gatt: BluetoothGatt? = null
    private var tx: BluetoothGattCharacteristic? = null
    private var mtu = 23
    private var kind = ""
    private var connecting: MethodChannel.Result? = null
    private var writing: MethodChannel.Result? = null
    private var generation = 0
    private var scanning: MethodChannel.Result? = null
    private var scanCallback: ScanCallback? = null
    private val discovered = linkedMapOf<String, BluetoothDevice>()
    private val serviceId = UUID.fromString("0000ae40-0000-1000-8000-00805f9b34fb")
    private val txId = UUID.fromString("0000ae41-0000-1000-8000-00805f9b34fb")
    private val rxId = UUID.fromString("0000ae42-0000-1000-8000-00805f9b34fb")
    private val cccdId = UUID.fromString("00002902-0000-1000-8000-00805f9b34fb")
    private var receiver: MidiReceiver? = null
    private val midiCallback = object : MidiManager.DeviceCallback() {
        override fun onDeviceRemoved(info: MidiDeviceInfo) {
            if (midiDevice?.info?.id == info.id) { sink?.success(mapOf("type" to "disconnected")); disconnect() }
        }
    }
    init {
        MethodChannel(messenger, "ai_tone/device").setMethodCallHandler(this)
        EventChannel(messenger, "ai_tone/device_events").setStreamHandler(this)
        midi?.registerDeviceCallback(midiCallback, main)
    }
    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) { sink = events }
    override fun onCancel(arguments: Any?) { sink = null }
    private fun emit(value: Any, token: Int = generation) { main.post { if (token == generation) sink?.success(value) } }
    private fun error(result: MethodChannel.Result, message: String) { result.error("device_error", message, null) }
    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "listUsb" -> {
                    val list = (midi?.devices ?: emptyArray()).filter { it.type == MidiDeviceInfo.TYPE_USB && it.inputPortCount > 0 && it.outputPortCount > 0 }
                    result.success(list.map { mapOf("id" to it.id.toString(), "name" to (it.properties.getString(MidiDeviceInfo.PROPERTY_PRODUCT) ?: it.properties.getString(MidiDeviceInfo.PROPERTY_NAME) ?: "USB MIDI ${it.id}"), "kind" to "usb") })
                }
                "scanBle" -> scan(result)
                "connect" -> {
                    if (connecting != null || scanning != null) { error(result, "Operação de conexão/busca em andamento"); return }
                    disconnect()
                    val requestedKind = call.argument<String>("kind") ?: ""
                    val id = call.argument<String>("id") ?: ""
                    kind = requestedKind
                    connecting = result
                    val token = generation
                    main.postDelayed({ if (token == generation && connecting != null) failConnect("Tempo de conexão excedido") }, 10000)
                    if (kind == "usb") connectUsb(id, token) else if (kind == "ble") connectBle(id) else failConnect("Transporte desconhecido")
                }
                "send" -> {
                    val bytes = call.argument<ByteArray>("bytes") ?: throw IllegalArgumentException("Pacote ausente")
                    if (bytes.size > 1024) { error(result, "Pacote grande demais"); return }
                    if (kind == "usb" && input != null) { input!!.send(bytes, 0, bytes.size); result.success(null) }
                    else if (kind == "ble" && gatt != null && tx != null) {
                        if (writing != null) { error(result, "Escrita BLE em andamento"); return }
                        // Não inventa fragmentação proprietária para imagem maior que o MTU.
                        if (bytes.size > mtu - 3) { error(result, "MTU BLE insuficiente para este pacote ($mtu). Use USB/OTG para enviar."); return }
                        writing = result
                        val characteristic = tx!!
                        characteristic.writeType = BluetoothGattCharacteristic.WRITE_TYPE_NO_RESPONSE
                        characteristic.value = bytes
                        if (!gatt!!.writeCharacteristic(characteristic)) { writing = null; error(result, "Android recusou a escrita BLE") }
                        else {
                            val token = generation
                            main.postDelayed({ if (token == generation && writing === result) { writing = null; error(result, "Tempo de escrita BLE excedido") } }, 5000)
                        }
                    } else error(result, "Pedaleira desconectada")
                }
                "disconnect" -> { disconnect(); result.success(null) }
                else -> result.notImplemented()
            }
        } catch (e: Exception) { error(result, e.message ?: "Falha no transporte") }
    }
    private fun connectUsb(id: String, token: Int) {
        val info = midi?.devices?.firstOrNull { it.id.toString() == id && it.type == MidiDeviceInfo.TYPE_USB }
        if (info == null) { failConnect("Dispositivo USB MIDI não encontrado. Confira o cabo OTG."); return }
        midi!!.openDevice(info, { device ->
            if (token != generation) { device?.close(); return@openDevice }
            if (device == null) { failConnect("Android não conseguiu abrir o dispositivo MIDI"); return@openDevice }
            try {
                midiDevice = device
                input = device.openInputPort(0)
                output = device.openOutputPort(0)
                if (input == null || output == null) { failConnect("Portas MIDI ocupadas ou indisponíveis. Feche M-EFCS."); return@openDevice }
                val newReceiver = object : MidiReceiver() {
                    override fun onSend(data: ByteArray, offset: Int, count: Int, timestamp: Long) {
                        emit(mapOf("type" to "data", "bytes" to data.copyOfRange(offset, offset + count)), token)
                    }
                }
                receiver = newReceiver
                output!!.connect(newReceiver)
                connecting?.success(mapOf("kind" to "usb", "name" to (info.properties.getString(MidiDeviceInfo.PROPERTY_PRODUCT) ?: "USB MIDI")))
                connecting = null
            } catch (e: Exception) { failConnect(e.message ?: "Falha ao abrir portas MIDI") }
        }, main)
    }
    private fun bluetoothAllowed(): Boolean {
        if (Build.VERSION.SDK_INT >= 31) return activity.checkSelfPermission(Manifest.permission.BLUETOOTH_SCAN) == PackageManager.PERMISSION_GRANTED && activity.checkSelfPermission(Manifest.permission.BLUETOOTH_CONNECT) == PackageManager.PERMISSION_GRANTED
        return activity.checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED
    }
    private fun scan(result: MethodChannel.Result) {
        if (!bluetoothAllowed()) { error(result, "Autorize Bluetooth/dispositivos próximos nas permissões do aplicativo"); return }
        if (scanning != null || connecting != null || gatt != null || midiDevice != null) { error(result, "Desconecte antes de buscar dispositivos"); return }
        val adapter = bluetooth?.adapter
        if (adapter == null || !adapter.isEnabled) { error(result, "Ative o Bluetooth do Android"); return }
        val scanner = adapter.bluetoothLeScanner
        if (scanner == null) { error(result, "Scanner Bluetooth indisponível"); return }
        discovered.clear(); scanning = result
        val callback = object : ScanCallback() {
            override fun onScanResult(type: Int, scanResult: ScanResult) {
                val name = scanResult.scanRecord?.deviceName ?: scanResult.device.name ?: ""
                val known = scanResult.scanRecord?.serviceUuids?.any { it.uuid == serviceId } == true
                if (known || name.contains("MK", true) || name.contains("M-VAVE", true)) discovered[scanResult.device.address] = scanResult.device
            }
            override fun onScanFailed(code: Int) {
                scanning?.let { error(it, "Falha na busca BLE: $code") }; scanning = null; scanCallback = null
            }
        }
        scanCallback = callback
        scanner.startScan(null, ScanSettings.Builder().setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY).build(), callback)
        main.postDelayed({
            if (scanning === result) {
                scanner.stopScan(callback); scanCallback = null
                result.success(discovered.values.map { mapOf("id" to it.address, "name" to (it.name ?: "M-EFCS BLE"), "kind" to "ble") }); scanning = null
            }
        }, 6500)
    }
    private fun connectBle(id: String) {
        if (!bluetoothAllowed()) { failConnect("Permissões Bluetooth ausentes"); return }
        val device = discovered[id]
        if (device == null) { failConnect("Busque novamente a pedaleira BLE"); return }
        gatt = device.connectGatt(activity, false, gattCallback, BluetoothDevice.TRANSPORT_LE)
    }
    private val gattCallback = object : BluetoothGattCallback() {
        override fun onConnectionStateChange(device: BluetoothGatt, status: Int, newState: Int) { main.post {
            if (device !== gatt) { device.close(); return@post }
            if (status != BluetoothGatt.GATT_SUCCESS || newState == BluetoothProfile.STATE_DISCONNECTED) {
                sink?.success(mapOf("type" to "disconnected")); failConnect("BLE desconectado (status $status)")
            } else if (newState == BluetoothProfile.STATE_CONNECTED && !device.discoverServices()) failConnect("Não foi possível descobrir serviços BLE")
        } }
        override fun onServicesDiscovered(device: BluetoothGatt, status: Int) { main.post {
            if (device !== gatt) return@post
            val service = device.getService(serviceId)
            tx = service?.getCharacteristic(txId)
            val rx = service?.getCharacteristic(rxId)
            if (status != BluetoothGatt.GATT_SUCCESS || tx == null || rx == null || (tx!!.properties and BluetoothGattCharacteristic.PROPERTY_WRITE_NO_RESPONSE) == 0 || (rx.properties and BluetoothGattCharacteristic.PROPERTY_NOTIFY) == 0) {
                failConnect("Serviço M-EFCS AE40/AE41/AE42 não encontrado. Não enviaremos comandos."); return@post
            }
            if (!device.requestMtu(517)) enableNotifications(device)
        } }
        override fun onMtuChanged(device: BluetoothGatt, value: Int, status: Int) { main.post {
            if (device !== gatt) return@post
            if (status == BluetoothGatt.GATT_SUCCESS) mtu = value
            enableNotifications(device)
        } }
        override fun onDescriptorWrite(device: BluetoothGatt, descriptor: BluetoothGattDescriptor, status: Int) { main.post {
            if (device !== gatt || descriptor.uuid != cccdId) return@post
            if (status != BluetoothGatt.GATT_SUCCESS) { failConnect("Não foi possível assinar respostas BLE"); return@post }
            connecting?.success(mapOf("kind" to "ble", "mtu" to mtu, "name" to (device.device.name ?: "M-EFCS BLE"))); connecting = null
        } }
        override fun onCharacteristicChanged(device: BluetoothGatt, characteristic: BluetoothGattCharacteristic) {
            if (Build.VERSION.SDK_INT < 33 && device === gatt && characteristic.uuid == rxId) emit(mapOf("type" to "data", "bytes" to characteristic.value.copyOf()))
        }
        override fun onCharacteristicChanged(device: BluetoothGatt, characteristic: BluetoothGattCharacteristic, value: ByteArray) {
            if (device === gatt && characteristic.uuid == rxId) emit(mapOf("type" to "data", "bytes" to value.copyOf()))
        }
        override fun onCharacteristicWrite(device: BluetoothGatt, characteristic: BluetoothGattCharacteristic, status: Int) { main.post {
            if (device !== gatt || characteristic.uuid != txId) return@post
            writing?.let { if (status == BluetoothGatt.GATT_SUCCESS) it.success(null) else error(it, "Falha de escrita BLE: $status") }; writing = null
        } }
    }
    private fun enableNotifications(device: BluetoothGatt) {
        val rx = device.getService(serviceId)?.getCharacteristic(rxId)
        val descriptor = rx?.getDescriptor(cccdId)
        if (rx == null || descriptor == null || !device.setCharacteristicNotification(rx, true)) { failConnect("Notificações BLE indisponíveis"); return }
        descriptor.value = BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE
        if (!device.writeDescriptor(descriptor)) failConnect("Falha ao habilitar notificações BLE")
    }
    private fun failConnect(message: String) { connecting?.let { error(it, message) }; connecting = null; disconnect() }
    fun disconnect() {
        generation++
        connecting?.let { error(it, "Conexão cancelada") }; connecting = null
        writing?.let { error(it, "Conexão encerrada durante escrita") }; writing = null
        try { receiver?.let { output?.disconnect(it) }; output?.close(); input?.close(); midiDevice?.close() } catch (_: Exception) {}
        receiver = null; output = null; input = null; midiDevice = null
        val old = gatt; gatt = null; tx = null; mtu = 23; kind = ""
        try { old?.disconnect(); old?.close() } catch (_: Exception) {}
    }
    fun dispose() {
        scanning?.let { error(it, "Busca cancelada") }; scanning = null
        try { scanCallback?.let { bluetooth?.adapter?.bluetoothLeScanner?.stopScan(it) } } catch (_: Exception) {}
        scanCallback = null
        disconnect(); midi?.unregisterDeviceCallback(midiCallback); sink = null
    }
}
