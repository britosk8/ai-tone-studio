import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _urlController = TextEditingController();
  bool _testing = false;
  String? _testResult;
  bool _testOk = false;

  @override
  void initState() {
    super.initState();
    _urlController.text = context.read<ApiService>().baseUrl;
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _testConnection() async {
    setState(() {
      _testing = true;
      _testResult = null;
    });
    try {
      context.read<ApiService>().setBaseUrl(_urlController.text.trim());
      final health = await context.read<ApiService>().checkHealth();
      if (mounted) {
        setState(() {
          _testing = false;
          _testOk = true;
          _testResult = 'Conectado! Versão: ${health['version'] ?? 'n/d'}';
        });
        await _saveUrl(_urlController.text.trim());
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _testing = false;
          _testOk = false;
          _testResult = 'Falha: $e';
        });
      }
    }
  }

  Future<void> _saveUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('backend_url', url);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ajustes')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Configuração do Backend',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(color: AppTheme.primaryGreen)),
          const SizedBox(height: 8),
          const Text(
            'Endereço do servidor backend (FastAPI). '
            'Para emulador Android: http://10.0.2.2:8000\n'
            'Para dispositivo físico na mesma rede: http://192.168.x.x:8000',
            style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _urlController,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              labelText: 'URL do backend',
              hintText: 'http://10.0.2.2:8000',
              filled: true,
              fillColor: AppTheme.bgCard,
              border: OutlineInputBorder(borderSide: BorderSide.none),
              prefixIcon: Icon(Icons.dns_outlined),
            ),
          ),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: _testing ? null : _testConnection,
            icon: _testing
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.black))
                : const Icon(Icons.wifi_find),
            label: Text(_testing ? 'Testando...' : 'Testar conexão'),
          ),
          if (_testResult != null) ...[
            const SizedBox(height: 8),
            Row(children: [
              Icon(
                _testOk ? Icons.check_circle : Icons.error,
                size: 16,
                color: _testOk ? AppTheme.primaryGreen : AppTheme.errorRed,
              ),
              const SizedBox(width: 8),
              Expanded(
                  child: Text(_testResult!,
                      style: TextStyle(
                        color:
                            _testOk ? AppTheme.primaryGreen : AppTheme.errorRed,
                        fontSize: 13,
                      ))),
            ]),
          ],
          const SizedBox(height: 32),
          const _SectionDivider('Sobre o aplicativo'),
          const SizedBox(height: 12),
          const _InfoRow('Versão', '1.2.3 — importação de presets'),
          const _InfoRow('Backend', 'Python 3.11 + FastAPI'),
          const _InfoRow('Análise', 'librosa 0.10.2'),
          const _InfoRow('Separação', 'Demucs htdemucs (opcional)'),
          const _InfoRow('Protocolo SysEx', 'Baseado em jpfaria/mvave (MIT)'),
          const SizedBox(height: 32),
          const _SectionDivider('Limitações conhecidas'),
          const SizedBox(height: 8),
          const _LimitationItem(
            'Análise da mixagem',
            'Sem separação de fontes, a análise é feita na mixagem completa com confiança BAIXA. '
                'Os presets são aproximações, não reproduções exatas do timbre original.',
          ),
          const _LimitationItem(
            'Transferência automática',
            'MK300: USB/OTG e BLE em teste físico. MK20: envio USB em teste no slot 150. '
                'O guia manual também está disponível.',
          ),
          const _LimitationItem(
            'Identificação de equipamento',
            'Impossível identificar com precisão o equipamento usado na gravação. '
                'O sistema estima características de timbre, não equipamento específico.',
          ),
        ],
      ),
    );
  }
}

class _SectionDivider extends StatelessWidget {
  final String label;
  const _SectionDivider(this.label);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(label,
            style: const TextStyle(
                color: AppTheme.primaryGreen, fontWeight: FontWeight.bold)),
        const SizedBox(width: 8),
        const Expanded(child: Divider()),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
              width: 120,
              child: Text(label,
                  style: const TextStyle(
                      color: AppTheme.textSecondary, fontSize: 13))),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }
}

class _LimitationItem extends StatelessWidget {
  final String title;
  final String description;

  const _LimitationItem(this.title, this.description);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline,
              size: 14, color: AppTheme.textSecondary),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 13)),
                const SizedBox(height: 2),
                Text(description,
                    style: const TextStyle(
                        fontSize: 12, color: AppTheme.textSecondary)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
