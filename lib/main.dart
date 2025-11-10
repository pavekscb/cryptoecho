import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui; 
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // ✅ ДОБАВЛЕНО для Clipboard
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false, 
      // ✅ ИМЯ ПРИЛОЖЕНИЯ
      title: 'CryptoEcho', 
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0E0E0E),
        cardColor: const Color(0xFF1E1E1E),
        canvasColor: const Color(0xFF0E0E0E), 
        textTheme: const TextTheme(bodyMedium: TextStyle(color: Colors.white)),
        appBarTheme: const AppBarTheme( 
          backgroundColor: Color(0xFF121212),
          titleTextStyle: TextStyle(color: Colors.white, fontSize: 20),
          iconTheme: IconThemeData(color: Colors.white),
        ),
      ),
      home: const PortfolioPage(),
    );
  }
}

class PortfolioPage extends StatefulWidget {
  const PortfolioPage({super.key});
  @override
  State<PortfolioPage> createState() => _PortfolioPageState();
}

class _PortfolioPageState extends State<PortfolioPage> {
  
  List<String> _coins = ['BTCUSDT', 'ETHUSDT', 'APTUSDT'];
  Map<String, double> _balances = {};
  Map<String, double> _prices = {};
  Map<String, double> _dayChange = {};
  
  Map<String, List<double>> _priceHistory = {}; 
  Map<String, double> _intervalChange = {}; 
  
  double _portfolioValue = 0.0;
  
  int _refreshInterval = 10; 
  int _seconds = 10;
  Timer? _timer;
  bool _isUpdating = false;
  
  bool _isDialogShowing = false;
  
  String? _selectedCoinForChart; 

  final ValueNotifier<int> _chartUpdateNotifier = ValueNotifier(0); 

  // Уведомления
  bool _notificationsEnabled = true;
  double _notificationThreshold = 0.01; 
  int _notificationDuration = 10; 
  
  @override
  void initState() {
    super.initState();
    _loadData().then((_) {
      _seconds = _refreshInterval;
      _fetchPrices();
      if (_coins.isNotEmpty) {
          _selectedCoinForChart = _coins.first;
      }
      _startTimer();
    });
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _coins = prefs.getStringList('coins') ?? ['BTCUSDT', 'ETHUSDT', 'APTUSDT'];
      _balances =
          Map<String, double>.from(json.decode(prefs.getString('balances') ?? '{}'));
      _refreshInterval = prefs.getInt('refreshInterval') ?? 10; 
      
      final historyJson = prefs.getString('priceHistory');
      if (historyJson != null) {
        final Map<String, dynamic> decoded = json.decode(historyJson);
        _priceHistory = decoded.map((key, value) => MapEntry(key, List<double>.from(value)));
      }
      
      _notificationsEnabled = prefs.getBool('notificationsEnabled') ?? true;
      _notificationThreshold = prefs.getDouble('notificationThreshold') ?? 0.01;
      _notificationDuration = prefs.getInt('notificationDuration') ?? 10; 
    });
  }

  Future<void> _saveData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('coins', _coins);
    await prefs.setString('balances', json.encode(_balances));
    await prefs.setInt('refreshInterval', _refreshInterval); 
    
    await prefs.setString('priceHistory', json.encode(_priceHistory)); 
    
    await prefs.setBool('notificationsEnabled', _notificationsEnabled);
    await prefs.setDouble('notificationThreshold', _notificationThreshold);
    await prefs.setInt('notificationDuration', _notificationDuration);
  }

  void _startTimer() {
    _timer?.cancel(); 
    
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_seconds > 0) {
        setState(() => _seconds--);
      } else {
        _fetchPrices();
        setState(() => _seconds = _refreshInterval); 
      }
    });
  }
  
  Future<void> _fetchPrices() async {
    if (_isUpdating) return;
    _isUpdating = true;

    try {
      for (var coin in _coins) {
        final url = 'https://api.binance.com/api/v3/ticker/24hr?symbol=${coin.toUpperCase()}';
        final response = await http.get(Uri.parse(url));

        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          final double newPrice = double.tryParse(data['lastPrice'] ?? '0') ?? 0.0;
          final double oldPrice = _prices[coin] ?? 0.0; 

          setState(() {
            _prices[coin] = newPrice;
            _dayChange[coin] =
                double.tryParse(data['priceChangePercent'] ?? '0') ?? 0.0;

            if (oldPrice > 0) {
              _intervalChange[coin] = ((newPrice - oldPrice) / oldPrice) * 100;
            } else {
              _intervalChange[coin] = 0.0;
            }

            // История: сохраняем 11 последних цен (10 интервалов)
            _priceHistory.putIfAbsent(coin, () => []);
            _priceHistory[coin]!.insert(0, newPrice); 
            if (_priceHistory[coin]!.length > 11) {
              _priceHistory[coin]!.removeLast(); 
            }
          });
        }
      }
      _calculatePortfolio();
      _saveData(); 
      
      if (mounted) {
          _chartUpdateNotifier.value++; 
      }
      
    } catch (e) {
      debugPrint('Ошибка загрузки цен: $e');
    } finally {
      _isUpdating = false;
      
      if (_notificationsEnabled) {
          _checkPriceAlerts();
      }
    }
  }

  void _checkPriceAlerts() {
    Map<String, double> triggeredAlerts = {};
    for (var coin in _coins) {
      final change = _intervalChange[coin] ?? 0.0;
      
      if (change.abs() >= _notificationThreshold) {
        triggeredAlerts[coin] = change;
      }
    }
    
    if (triggeredAlerts.isNotEmpty) {
        _showPriceAlertDialog(triggeredAlerts);
    }
  }

  void _showPriceAlertDialog(Map<String, double> alerts) {
    if (_isDialogShowing || alerts.isEmpty) { // ✅ ИСПРАВЛЕНИЕ 1: Не вызывать, если пусто
        return;
    }
    
    int countdown = _notificationDuration;
    Timer? dialogTimer; 
    
    _isDialogShowing = true; 
    
    showDialog(
      context: context,
      barrierDismissible: true, 
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateSB) {
            
            if (dialogTimer == null) {
              dialogTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
                if (countdown > 1 && mounted) {
                  setStateSB(() {
                    countdown--;
                  });
                } else {
                  timer.cancel();
                  if (Navigator.of(context).canPop()) {
                      Navigator.of(context).pop();
                  }
                }
              });
            }

            return AlertDialog(
              backgroundColor: const Color(0xFF1E1E1E),
              title: const Text('🚨 Изменение цены!', 
                  style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold)),
              
              content: SizedBox(
                  // ✅ ИСПРАВЛЕНИЕ 2: Явно задаем высоту, чтобы избежать проблем рендеринга
                  height: alerts.length * 70.0, 
                  width: double.maxFinite,
                  child: ListView(
                      shrinkWrap: true,
                      children: alerts.entries.map((entry) {
                          final coin = entry.key;
                          final change = entry.value;
                          final isPositive = change > 0;
                          final color = isPositive ? Colors.greenAccent : Colors.red.shade300;
                          final sign = isPositive ? '+' : '';
                          final icon = isPositive ? Icons.arrow_upward : Icons.arrow_downward;
                          
                          return ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: Icon(icon, color: color),
                              
                              title: Text(coin, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                              
                              subtitle: Row(
                                  children: [
                                      const Text(
                                          'Прогноз: ',
                                          style: TextStyle(color: Colors.white70, fontSize: 14),
                                      ),
                                      _buildLastHistoryIcon(coin),
                                  ],
                              ),
                              
                              trailing: Text(
                                  '$sign${change.toStringAsFixed(2)}%',
                                  style: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.bold),
                              ),
                          );
                      }).toList(),
                  ),
              ),
              actions: [
                Text(
                  '${countdown} с', 
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 14)),
                const Spacer(),
                TextButton(
                  onPressed: () {
                    dialogTimer?.cancel(); 
                    Navigator.pop(context);
                  },
                  child: const Text('Закрыть', style: TextStyle(color: Colors.amber)),
                ),
              ],
            );
          },
        );
      }
    ).then((_) {
      dialogTimer?.cancel();
      _isDialogShowing = false; 
    });
  }


  void _calculatePortfolio() {
    double total = 0;
    for (var coin in _coins) {
      final balance = _balances[coin] ?? 0;
      final price = _prices[coin] ?? 0;
      total += balance * price;
    }
    setState(() => _portfolioValue = total);
  }
  
  void _addCoinDialog() {
    final controller = TextEditingController();
    _isDialogShowing = true; 
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('Добавить монету', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Введите символ монеты (например: BTCUSDT, DOGSUSDT, NOTUSDT)',
              style: TextStyle(color: Colors.grey, fontSize: 13),
            ),
            const SizedBox(height: 15),
            TextField(
              controller: controller,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'ID монеты',
                labelStyle: TextStyle(color: Colors.grey),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              final id = controller.text.trim().toUpperCase();
              if (id.isNotEmpty && !_coins.contains(id)) {
                setState(() {
                  _coins.add(id);
                  _balances[id] = 0.0;
                  _priceHistory[id] = []; 
                  if (_selectedCoinForChart == null) {
                      _selectedCoinForChart = id;
                  }
                });
                _saveData();
                _fetchPrices();
              }
              Navigator.pop(context);
            },
            child: const Text('Добавить', style: TextStyle(color: Colors.amber)),
          ),
        ],
      ),
    ).then((_) => _isDialogShowing = false); 
  }

  void _editBalanceDialog(String coin) {
    final controller =
        TextEditingController(text: _balances[coin]?.toString() ?? '0');
    _isDialogShowing = true; 
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: Text('Изменить баланс $coin',
            style: const TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            labelText: 'Количество монет',
            labelStyle: TextStyle(color: Colors.grey),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              final value = double.tryParse(controller.text) ?? 0.0;
              setState(() {
                _balances[coin] = value;
              });
              _saveData();
              _calculatePortfolio();
              Navigator.pop(context);
            },
            child: const Text('Сохранить', style: TextStyle(color: Colors.amber)),
          ),
          TextButton(
            onPressed: () {
              setState(() {
                _coins.remove(coin);
                _balances.remove(coin);
                _priceHistory.remove(coin); 
                if (_selectedCoinForChart == coin) {
                    _selectedCoinForChart = _coins.isNotEmpty ? _coins.first : null;
                }
              });
              _saveData();
              Navigator.pop(context);
            },
            child: const Text('Удалить монету', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    ).then((_) => _isDialogShowing = false); 
  }

  void _showAnalyticsDialog() {
      if (_coins.isEmpty) {
          _isDialogShowing = true;
          showDialog(
              context: context,
              builder: (context) => AlertDialog(
                  backgroundColor: const Color(0xFF1E1E1E),
                  title: const Text('Аналитика', style: TextStyle(color: Colors.white)),
                  content: const Text('Добавьте монеты в портфель, чтобы увидеть аналитику.', style: TextStyle(color: Colors.white70)),
                  actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Закрыть', style: TextStyle(color: Colors.amber)),
                      ),
                  ],
              )
          ).then((_) => _isDialogShowing = false);
          return;
      }
      
      if (_selectedCoinForChart == null || !_coins.contains(_selectedCoinForChart)) {
          _selectedCoinForChart = _coins.first;
      }

      _isDialogShowing = true;
      showDialog(
          context: context,
          builder: (context) {
              return StatefulBuilder(
                  builder: (context, setStateSB) {
                      final selectedCoin = _selectedCoinForChart!;
                      // История от старой цены к новой (reversed)
                      final historyData = (_priceHistory[selectedCoin] ?? []).reversed.toList(); 
                      
                      return AlertDialog(
                          backgroundColor: const Color(0xFF1E1E1E),
                          title: Text('Аналитика цены (Live) - $selectedCoin', style: const TextStyle(color: Colors.white)), // Добавлено имя монеты
                          content: SizedBox(
                              width: 300,
                              height: 350, // Немного увеличена высота для лучшего отображения подписей
                              child: Column(
                                  children: [
                                      DropdownButtonFormField<String>(
                                          value: selectedCoin,
                                          dropdownColor: const Color(0xFF1E1E1E),
                                          style: const TextStyle(color: Colors.white),
                                          decoration: const InputDecoration(
                                              labelText: 'Выберите монету',
                                              labelStyle: TextStyle(color: Colors.amber),
                                              border: OutlineInputBorder(),
                                          ),
                                          items: _coins.map((String coin) {
                                              return DropdownMenuItem<String>(
                                                  value: coin,
                                                  child: Text(coin),
                                              );
                                          }).toList(),
                                          onChanged: (String? newValue) {
                                              if (newValue != null) {
                                                  setStateSB(() {
                                                      _selectedCoinForChart = newValue;
                                                  });
                                              }
                                          },
                                      ),
                                      
                                      const SizedBox(height: 20),
                                      
                                      // ValueListenableBuilder для "живого" обновления графика
                                      Expanded(
                                          child: historyData.length < 2
                                              ? const Center(child: Text('Недостаточно данных для графика.', style: TextStyle(color: Colors.white70)))
                                              : ValueListenableBuilder<int>(
                                                  valueListenable: _chartUpdateNotifier,
                                                  builder: (context, value, child) {
                                                      // Получаем свежую историю для выбранной монеты
                                                      final freshHistoryData = (_priceHistory[_selectedCoinForChart!] ?? []).reversed.toList();
                                                      final currentPrice = _prices[_selectedCoinForChart!] ?? 0.0;
                                                      return CoinPriceChart(
                                                          history: freshHistoryData,
                                                          currentPrice: currentPrice, // Передаем текущую цену
                                                      );
                                                  },
                                              )
                                      ), 
                                  ],
                              ),
                          ),
                          actions: [
                              TextButton(
                                  onPressed: () => Navigator.pop(context),
                                  child: const Text('Закрыть', style: TextStyle(color: Colors.amber)),
                              ),
                          ],
                      );
                  },
              );
          }
      ).then((_) => _isDialogShowing = false);
  }

  void _helpDialog() {
    const String evmWallet = '0x3EB6aA29C796A8271C5A5ab84bEe4f91df280632'; // ✅ EVM Кошелек
    _isDialogShowing = true; 
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('Справка и Поддержка', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Поддержка приложения:',
                style: TextStyle(color: Colors.white70)),
            TextButton(
              onPressed: () => _launchUrl('https://t.me/cripto_karta'),
              child: const Text('Чат телеграмм канала Крипто карта',
                  style: TextStyle(
                      color: Colors.amber,
                      decoration: TextDecoration.underline)),
            ),
            
            // --- НОВЫЙ РАЗДЕЛ ПОМОЩЬ ПРОЕКТУ ---
            const Divider(color: Colors.grey),
            const Text(
                'Помочь проекту',
                style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16),
            ),
            const SizedBox(height: 8),
            const Text(
                'Ваша поддержка помогает нам развивать приложение. Вы можете отправить любые токены/монеты, совместимые с EVM (Ethereum, BSC, Polygon и т.д.), на адрес ниже.',
                style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 8),
            Row(
                children: [
                    Expanded(
                        child: SelectableText( // Для удобства копирования
                            evmWallet,
                            style: const TextStyle(color: Colors.greenAccent, fontSize: 12),
                        ),
                    ),
                    IconButton(
                        icon: const Icon(Icons.copy, color: Colors.amber, size: 20),
                        onPressed: () {
                            Clipboard.setData(const ClipboardData(text: evmWallet));
                            ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text('Адрес EVM кошелька скопирован!'),
                                    duration: Duration(seconds: 2),
                                ),
                            );
                        },
                    ),
                ],
            ),
            // --- КОНЕЦ НОВОГО РАЗДЕЛА ---

            const Divider(color: Colors.grey),
             TextButton(
              onPressed: () => _launchUrl('https://github.com/pavekscb/cryptoecho/releases'),
              child: const Text('ПОСЛЕДНЯЯ ВЕРСИЯ (.APK)',
                  style: TextStyle(
                      color: Colors.amber,
                      decoration: TextDecoration.underline)),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Закрыть', style: TextStyle(color: Colors.amber)),
          ),
        ],
      ),
    ).then((_) => _isDialogShowing = false); 
  }

  void _settingsDialog() {
    double tempInterval = _refreshInterval.toDouble();
    bool tempNotificationsEnabled = _notificationsEnabled; 
    double tempNotificationThreshold = _notificationThreshold; 
    double tempNotificationDuration = _notificationDuration.toDouble(); 

    _isDialogShowing = true; 
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateSB) {
          return AlertDialog(
            backgroundColor: const Color(0xFF1E1E1E),
            title: const Text('Настройки', style: TextStyle(color: Colors.white)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Уведомления о цене', style: TextStyle(color: Colors.white)),
                  value: tempNotificationsEnabled,
                  onChanged: (bool value) {
                    setStateSB(() {
                      tempNotificationsEnabled = value;
                    });
                  },
                  activeColor: Colors.amber,
                ),
                
                const SizedBox(height: 10),
                const Text('Порог изменения цены для уведомлений:',
                    style: TextStyle(color: Colors.white70)),
                Text(
                  '${tempNotificationThreshold.toStringAsFixed(2)}%',
                  style: const TextStyle(
                      color: Colors.amber,
                      fontSize: 18,
                      fontWeight: FontWeight.bold),
                ),
                Slider(
                  value: tempNotificationThreshold,
                  min: 0.01,
                  max: 1.0, 
                  divisions: 99, 
                  label: '${tempNotificationThreshold.toStringAsFixed(2)}%',
                  onChanged: (double newValue) {
                    setStateSB(() {
                      tempNotificationThreshold = newValue;
                    });
                  },
                  activeColor: Colors.amber,
                  inactiveColor: Colors.grey[700],
                ),
                
                const Divider(color: Colors.grey),
                
                const Text('Время показа уведомления:',
                    style: TextStyle(color: Colors.white70)),
                Text(
                  '${tempNotificationDuration.toInt()} секунд',
                  style: const TextStyle(
                      color: Colors.amber,
                      fontSize: 18,
                      fontWeight: FontWeight.bold),
                ),
                Slider(
                  value: tempNotificationDuration,
                  min: 1,
                  max: 10, 
                  divisions: 9, 
                  label: '${tempNotificationDuration.toInt()} с',
                  onChanged: (double newValue) {
                    setStateSB(() {
                      tempNotificationDuration = newValue;
                    });
                  },
                  activeColor: Colors.amber,
                  inactiveColor: Colors.grey[700],
                ),

                const Divider(color: Colors.grey),

                const Text('Интервал обновления цен:',
                    style: TextStyle(color: Colors.white70)),
                Text(
                  '${tempInterval.toInt()} секунд',
                  style: const TextStyle(
                      color: Colors.amber,
                      fontSize: 18,
                      fontWeight: FontWeight.bold),
                ),
                Slider(
                  value: tempInterval,
                  min: 10,
                  max: 100, 
                  divisions: (100 - 10), 
                  label: '${tempInterval.toInt()} с',
                  onChanged: (double newValue) {
                    setStateSB(() {
                      tempInterval = newValue;
                    });
                  },
                  activeColor: Colors.amber,
                  inactiveColor: Colors.grey[700],
                ),
                
                const Divider(color: Colors.grey),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  setState(() {
                    _refreshInterval = tempInterval.toInt();
                    _seconds = _refreshInterval; 
                    _notificationsEnabled = tempNotificationsEnabled;
                    _notificationThreshold = tempNotificationThreshold;
                    _notificationDuration = tempNotificationDuration.toInt(); 
                  });
                  _saveData();
                  _startTimer();
                  Navigator.pop(context);
                },
                child: const Text('Сохранить', style: TextStyle(color: Colors.amber)),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Отмена', style: TextStyle(color: Colors.white70)),
              ),
            ],
          );
        },
      ),
    ).then((_) => _isDialogShowing = false); 
  }

  Future<void> _launchUrl(String urlString) async {
    final Uri url = Uri.parse(urlString);
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } else {
      debugPrint('Не удалось открыть $urlString');
    }
  }

  String _formatChange(double? change) {
    if (change == null) return '0.00%';
    final sign = change > 0 ? '+' : '';
    return '$sign${change.toStringAsFixed(2)}%';
  }

  TextSpan _buildColoredChange(double? change) {
    if (change == null) {
      return const TextSpan(text: '0.00%', style: TextStyle(color: Colors.grey));
    }
    Color color = Colors.grey;
    String arrow = '';
    if (change > 0) {
      color = Colors.greenAccent;
      arrow = ' ▲';
    } else if (change < 0) {
      color = Colors.red.shade300!;
      arrow = ' ▼';
    }
    return TextSpan(
      text: '${_formatChange(change)}$arrow',
      style: TextStyle(color: color),
    );
  }

  Widget _buildLastHistoryIcon(String coin) {
      final history = _priceHistory[coin] ?? [];
      if (history.length < 2) {
        return const Text('—', style: TextStyle(color: Colors.grey, fontSize: 14));
      }

      Color color = Colors.grey;
      String arrow = '—';

      if (history[0] > history[1]) {
        color = Colors.greenAccent;
        arrow = '▲'; 
      } else if (history[0] < history[1]) {
        color = Colors.red.shade300!;
        arrow = '▼';
      }
      
      return Text(
        arrow,
        style: TextStyle(color: color, fontSize: 14),
      );
  }

  Widget _buildPriceHistoryIcons(String coin) {
    final history = _priceHistory[coin] ?? [];
    if (history.length < 2) {
      return const Text('Нет данных', style: TextStyle(color: Colors.grey));
    }

    List<Widget> icons = [];
    
    for (int i = 0; i < history.length - 1; i++) {
      Color color = Colors.grey;
      String arrow = '—';

      if (history[i] > history[i + 1]) {
        color = Colors.greenAccent;
        arrow = '▲'; 
      } else if (history[i] < history[i + 1]) {
        color = Colors.red.shade300!;
        arrow = '▼';
      }
      
      icons.insert(0, Padding( 
        padding: const EdgeInsets.only(left: 2),
        child: Text(
          arrow,
          style: TextStyle(color: color, fontSize: 14),
        ),
      ));
    }
    
    if (icons.length > 10) {
      icons = icons.sublist(icons.length - 10);
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: icons,
    );
  }
  
  Future<void> _launchBinance(String coin) async {
    final url = 'https://www.binance.com/en/trade/${coin.toUpperCase()}?type=spot';
    if (await canLaunchUrl(Uri.parse(url))) {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _chartUpdateNotifier.dispose(); 
    super.dispose();
  }

  Future<void> _refresh() async {
    setState(() => _seconds = _refreshInterval);
    _startTimer();
    await _fetchPrices();
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        // ✅ ИМЯ ПРИЛОЖЕНИЯ
        title: const Text('CryptoEcho'), 
        actions: [
          IconButton(onPressed: _addCoinDialog, icon: const Icon(Icons.add)),
          IconButton(onPressed: _showAnalyticsDialog, icon: const Icon(Icons.bar_chart)), 
          IconButton(onPressed: _helpDialog, icon: const Icon(Icons.help_outline)), 
          IconButton(onPressed: _settingsDialog, icon: const Icon(Icons.settings)),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        color: Colors.amber,
        child: ListView(
          children: [
            for (var coin in _coins)
              Card(
                color: const Color(0xFF1E1E1E),
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: ListTile(
                  onTap: () => _editBalanceDialog(coin),
                  onLongPress: () => _launchBinance(coin),
                  
                  title: RichText(
                    overflow: TextOverflow.ellipsis,
                    text: TextSpan(
                      style: const TextStyle(color: Colors.white70, fontSize: 14),
                      children: [
                        TextSpan(
                          text: '$coin',
                          style: const TextStyle(
                              color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                        const TextSpan(text: ' - Изм.: 24 ч: '),
                        _buildColoredChange(_dayChange[coin]),
                      ],
                    ),
                  ),
                  
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Цена: \$${_prices[coin]?.toStringAsFixed(8) ?? '—'}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      ),
                      
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.start, // ✅ ИЗМЕНЕНИЕ 1: Для лучшей верстки
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Стоимость: \$${((_balances[coin] ?? 0) * (_prices[coin] ?? 0)).toStringAsFixed(2)}',
                                style: const TextStyle(color: Colors.amber, fontSize: 16, fontWeight: FontWeight.bold),
                              ),
                              // ✅ ИЗМЕНЕНИЕ 1: Вывод баланса под стоимостью с сокращенной точностью
                              Text( 
                                '${_balances[coin]?.toStringAsFixed(2) ?? '0.00'} ${_coins.contains(coin) ? coin.replaceAll('USDT', '') : ''}', // 100.01 BTC
                                style: const TextStyle(color: Colors.amber, fontSize: 14),
                              ),
                            ],
                          ),
                          // Text(
                          //   '${_balances[coin]?.toStringAsFixed(4) ?? '0'}', // УДАЛЕНО: Перенесено в Column
                          //   style: const TextStyle(color: Colors.amber, fontSize: 16),
                          // ),
                          
                        ],
                      ),
                      
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Text(
                            'Прогноз: ',
                            style: TextStyle(color: Colors.white70, fontSize: 14),
                          ),
                          _buildPriceHistoryIcons(coin), 
                        ],
                      ),
                      
                      RichText(
                        text: TextSpan(
                          style: const TextStyle(color: Colors.grey, fontSize: 14),
                          children: [
                            const TextSpan(text: 'Тренд за интервал: '),
                            _buildColoredChange(_intervalChange[coin]),
                          ]
                        ),
                      ),
                    ],
                  ),
                  
                  trailing: const SizedBox.shrink(), 
                ),
              ),
            const Divider(color: Colors.grey),
            
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Общая сумма:',
                    style: TextStyle(
                        fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                  Flexible(
                    child: Text(
                      '\$${_portfolioValue.toStringAsFixed(2)}',
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Colors.amberAccent),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: LinearProgressIndicator(
                value: _seconds / _refreshInterval,
                color: Colors.amberAccent,
                backgroundColor: Colors.grey[800],
                minHeight: 6,
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: TextButton(
                onPressed: _refresh,
                child: Text(
                  'Обновление через: $_seconds с',
                  style: const TextStyle(color: Colors.white70),
                ),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}


// ----------------------------------------------------------------------
// ВИДЖЕТ: Простой линейный график с CustomPainter
// ----------------------------------------------------------------------

class CoinPriceChart extends StatelessWidget {
    final List<double> history; 
    final double currentPrice; 

    const CoinPriceChart({required this.history, required this.currentPrice, super.key});

    @override
    Widget build(BuildContext context) {
        return CustomPaint(
            painter: LineChartPainter(history: history, currentPrice: currentPrice),
            child: Container(),
        );
    }
}

class LineChartPainter extends CustomPainter {
    final List<double> history;
    final double currentPrice; 

    LineChartPainter({required this.history, required this.currentPrice});

    // Хелпер для рисования пунктирных линий
    void _drawDashedPath(Canvas canvas, Path path, Paint paint, double dash, double gap) {
        final ui.PathMetrics metrics = path.computeMetrics(); 
        for (final ui.PathMetric metric in metrics) { 
            double distance = 0.0;
            while (distance < metric.length) {
                canvas.drawPath(
                    metric.extractPath(distance, distance + dash),
                    paint,
                );
                distance += dash + gap;
            }
        }
    }
    
    // ✅ Расчет вероятностей на основе последних 5 интервалов
    Map<String, int> _calculateForecastProbabilities() {
        if (history.length < 3) return {'same': 50, 'reverse': 50}; // Дефолт 50/50

        // Определяем направление последнего движения (которое мы продолжаем/реверсируем)
        final bool lastMoveUp = history.last > history[history.length - 2];

        // Анализируем последние 5 интервалов
        int sameDirectionCount = 0;
        int oppositeDirectionCount = 0;
        
        // Начинаем с предпоследней точки (интервал history[i-1] -> history[i])
        for (int i = history.length - 2; i >= 1 && i >= history.length - 6; i--) {
            final bool currentMoveUp = history[i] > history[i - 1];
            if (currentMoveUp == lastMoveUp) {
                sameDirectionCount++;
            } else {
                oppositeDirectionCount++;
            }
        }
        
        final int totalRecent = sameDirectionCount + oppositeDirectionCount;
        if (totalRecent == 0) return {'same': 50, 'reverse': 50}; 

        // Эвристика: 50% + 5% * (кол-во совпадений - кол-во несовпадений)
        final int difference = sameDirectionCount - oppositeDirectionCount;
        final int adjustment = difference * 5; 
        
        final int pSame = (50 + adjustment).clamp(25, 75); // Ограничиваем 25% и 75%
        final int pReverse = 100 - pSame;
        
        return {'same': pSame, 'reverse': pReverse};
    }

    // Хелпер для форматирования цены (✅ УСЛОВНАЯ ТОЧНОСТЬ)
    String _formatPrice(double price) {
        if (price >= 1000) {
            return price.toStringAsFixed(2); // Высокая цена: меньше точность (105306.12)
        } else if (price >= 1) {
            return price.toStringAsFixed(4); // Средняя цена: 4 знака (3.2312)
        } else if (price >= 0.001) {
            return price.toStringAsFixed(4);
        } else {
            return price.toStringAsFixed(8); 
        }
    }


    // ✅ Модифицированный drawForecast для отрисовки процента и сдвига текста
    void _drawForecast(Canvas canvas, Size size, double initialDelta, Color color, int probability, double lastX, double lastY, double stepX, double actualMin, double actualMax, double actualRange, Function(double) getY, double yOffsetAdjustment) {
        const int numPredictionPoints = 3; 

        final forecastPaint = Paint()
            ..color = color
            ..strokeWidth = 2.0
            ..style = PaintingStyle.stroke;

        final forecastPath = Path();
        forecastPath.moveTo(lastX, lastY); // Начинаем с последней точки истории
        
        double currentPrice = history.last;
        double currentX = lastX;
        
        final double actualMinForClamp = actualMin;
        final double actualMaxForClamp = actualMax;

        // Точки для расчета центральной Y-координаты текста
        double price1 = 0.0, price2 = 0.0;
        
        for (int i = 1; i <= numPredictionPoints; i++) {
            currentPrice += initialDelta; 
            currentX += stepX; 
            
            // Клампим цену для отрисовки, чтобы она оставалась в разумном диапазоне
            double predictedPrice = currentPrice.clamp(actualMinForClamp, actualMaxForClamp);

            forecastPath.lineTo(currentX, getY(predictedPrice));
            
            if (i == 1) price1 = predictedPrice;
            if (i == 2) price2 = predictedPrice;
        }

        _drawDashedPath(canvas, forecastPath, forecastPaint, 6.0, 4.0);
        
        // --- Рисование процента вероятности ---
        
        // Находим приблизительную среднюю точку на прогнозной линии
        final double midX = lastX + 1.5 * stepX; 
        final double midY = (getY(price1) + getY(price2)) / 2.0; 
        
        final textPainter = TextPainter(
            text: TextSpan(
                text: '${probability}%',
                style: TextStyle(
                    color: color.withOpacity(0.9), 
                    fontSize: 20.0, 
                    fontWeight: FontWeight.bold,
                    shadows: const [ 
                        Shadow(
                            blurRadius: 1.0,
                            color: Colors.black,
                            offset: Offset(0, 0),
                        )
                    ]
                ),
            ),
            textDirection: TextDirection.ltr,
        );
        textPainter.layout();
        
        // Рисуем текст немного выше средней точки + применяем вертикальный сдвиг для предотвращения наложения
        textPainter.paint(
            canvas, 
            Offset(midX - textPainter.width / 2, midY - textPainter.height - 3 + yOffsetAdjustment),
        );
    }


    @override
    void paint(Canvas canvas, Size size) {
        if (history.length < 2) return;
        
        // Отступы для меток по оси Y (справа)
        const double labelWidth = 50.0; 
        final chartWidth = size.width - labelWidth;
        final chartHeight = size.height;

        // Определяем диапазон, включая потенциальный небольшой буфер
        final double minPrice = history.reduce((a, b) => a < b ? a : b);
        final double maxPrice = history.reduce((a, b) => a > b ? a : b);
        final double range = maxPrice - minPrice;
        
        final double buffer = range * 0.1; // 10% буфер
        final double actualMin = minPrice - buffer;
        final double actualMax = maxPrice + buffer;
        final double actualRange = actualMax - actualMin;

        const int numPredictionPoints = 3; 
        final int totalIntervals = (history.length > 0 ? history.length - 1 : 0) + numPredictionPoints; 

        final double stepX = totalIntervals > 0 ? chartWidth / totalIntervals : chartWidth;
        
        // --- 1. Вспомогательная функция Y-координаты ---
        double getY(double price) {
            if (actualRange == 0) return chartHeight / 2;
            final normalized = (price - actualMin) / actualRange;
            // Инвертируем, так как (0,0) вверху
            return chartHeight * (1.0 - normalized); 
        }
        
        // --- 2. Рисование сетки и меток (Оси Y) (✅ УМЕНЬШЕН ШРИФТ) ---
        final gridPaint = Paint()
            ..color = Colors.grey.withOpacity(0.15)
            ..strokeWidth = 0.5
            ..style = PaintingStyle.stroke;
            
        const int numLines = 5; // 5 горизонтальных линий
        
        // Цены для подписей
        final double priceStep = actualRange / (numLines - 1);
        
        for (int i = 0; i < numLines; i++) {
            final double price = actualMin + priceStep * i;
            final double y = getY(price);

            // Рисование сетки
            canvas.drawLine(Offset(0, y), Offset(chartWidth, y), gridPaint);

            // Рисование меток цен справа
            final textPainter = TextPainter(
                text: TextSpan(
                    text: _formatPrice(price),
                    style: TextStyle(
                        color: Colors.white70,
                        fontSize: 10.0, // ИЗМЕНЕНИЕ: Уменьшен до 10.0 для умещения крупных цен
                        fontWeight: FontWeight.w300,
                    ),
                ),
                textDirection: TextDirection.ltr,
            );
            textPainter.layout();
            
            // Выравнивание по правому краю области графика
            textPainter.paint(
                canvas,
                Offset(chartWidth + 5.0, y - textPainter.height / 2),
            );
        }

        // --- 3. Рисование исторической линии (сплошная) ---
        final historyPaint = Paint()
            ..color = history.last > history.first ? Colors.greenAccent : Colors.red.shade300!
            ..strokeWidth = 2.0
            ..style = PaintingStyle.stroke;
            
        final historyPath = Path();
        historyPath.moveTo(0, getY(history.first));

        for (int i = 1; i < history.length; i++) {
            historyPath.lineTo(i * stepX, getY(history[i]));
        }

        canvas.drawPath(historyPath, historyPaint);
        
        // Новая координата X для последней точки истории
        final lastX = (history.length - 1) * stepX; 
        final lastY = getY(history.last);
        
        // Рисуем точку на текущей цене
        canvas.drawCircle(Offset(lastX, lastY), 4.0, Paint()..color = historyPaint.color..style = PaintingStyle.fill);
        
        // --- 4. Метка текущей цены (✅ СДВИНУТА ВЛЕВО) ---
        final currentPricePainter = TextPainter(
            text: TextSpan(
                text: _formatPrice(currentPrice),
                style: TextStyle(
                    color: Colors.amber, 
                    fontSize: 20.0, 
                    fontWeight: FontWeight.bold,
                ),
            ),
            textDirection: TextDirection.ltr,
        );
        currentPricePainter.layout();
        
        // Рисуем над точкой, сдвигая центр на 15.0 влево
        currentPricePainter.paint(
            canvas, 
            Offset(lastX - currentPricePainter.width / 2 - 15.0, lastY - 15), 
        );


        // --- 5. Рисование прогнозных линий (пунктир) ---
        
        final Map<String, int> probabilities = _calculateForecastProbabilities();
        final int pSameTrend = probabilities['same']!;
        final int pReverseTrend = probabilities['reverse']!;

        // Разница в цене между последней и предпоследней точкой (текущий тренд)
        final double deltaPrice = history.last - history[history.length - 2]; 

        if (deltaPrice >= 0) {
            // Сценарий 1: Продолжение тренда (UP) - ВЕРХНЯЯ линия
            final Color color1 = Colors.greenAccent; 
            // Сдвиг вверх (отрицательное значение)
            _drawForecast(canvas, size, deltaPrice, color1, pSameTrend, lastX, lastY, stepX, actualMin, actualMax, actualRange, getY, -25.0); 

            // Сценарий 2: Реверс тренда (DOWN) - НИЖНЯЯ линия
            final Color color2 = Colors.red.shade400.withOpacity(0.5); 
            // Сдвиг вниз (положительное значение)
            _drawForecast(canvas, size, -deltaPrice, color2, pReverseTrend, lastX, lastY, stepX, actualMin, actualMax, actualRange, getY, 25.0); 
        } else {
            // Сценарий 1: Продолжение тренда (DOWN) - НИЖНЯЯ линия
            final Color color1 = Colors.red.shade400; 
            // Сдвиг вниз (положительное значение)
            _drawForecast(canvas, size, deltaPrice, color1, pSameTrend, lastX, lastY, stepX, actualMin, actualMax, actualRange, getY, 25.0); 
            
            // Сценарий 2: Реверс тренда (UP) - ВЕРХНЯЯ линия
            final Color color2 = Colors.greenAccent.withOpacity(0.5); 
            // Сдвиг вверх (отрицательное значение)
            _drawForecast(canvas, size, -deltaPrice, color2, pReverseTrend, lastX, lastY, stepX, actualMin, actualMax, actualRange, getY, -25.0); 
        }
    }

    @override
    bool shouldRepaint(covariant LineChartPainter oldDelegate) {
        return oldDelegate.history != history || oldDelegate.currentPrice != currentPrice;
    }
}
