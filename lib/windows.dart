// windows.dart

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart'; // ✅ Используем url_launcher

// Хелпер для запуска URL
Future<void> _launchUrl(String urlString) async {
    final Uri url = Uri.parse(urlString);
    // Открываем внешнюю ссылку (например, в новой вкладке браузера или внешнем приложении)
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } else {
      debugPrint('Не удалось открыть $urlString');
    }
}

// ✅ Новый виджет-диалог со списком инструментов
class InfoToolsDialog extends StatelessWidget {
  const InfoToolsDialog({super.key});

  @override
  Widget build(BuildContext context) {
    // Внутренний список виджетов
    List<Widget> toolList = [
        // 1. Криптовалютный индекс страха и жадности
        _buildToolItem(
            context: context,
            icon: Icons.sentiment_very_satisfied,
            title: '1. Криптовалютный индекс страха и жадности',
            url: 'https://www.binance.com/ru-UA/square/fear-and-greed-index',
        ),
        // 2. TradingView
        _buildToolItem(
            context: context,
            icon: Icons.ssid_chart,
            title: '2. Индекс альткоин сезона',
            url: 'https://coinmarketcap.com/charts/altcoin-season-index/',
        ),
        // 3. DefiLlama
        _buildToolItem(
            context: context,
            icon: Icons.donut_large,
            title: '3. Доминация BTC',
            url: 'https://coinmarketcap.com/charts/bitcoin-dominance/',
        ),
    ];

    return AlertDialog(
      // Темная тема для диалога
      backgroundColor: const Color(0xFF1E1E1E), 
      title: const Text(
          'Полезные крипто инструменты:', 
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)
      ),
      
      content: SingleChildScrollView(
        child: ListBody(
          children: toolList,
        ),
      ),
      
      actions: [
        // ✅ Кнопка "Закрыть"
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Закрыть', style: TextStyle(color: Colors.amber)),
        ),
      ],
    );
  }
  
  // Вспомогательный метод для создания одного элемента в списке
  Widget _buildToolItem({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String url,
  }) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: Colors.amber),
      title: Text(title, style: const TextStyle(color: Colors.white)),
      subtitle: Text(
          url,
          style: const TextStyle(color: Colors.white54, fontSize: 11),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
      ),
      onTap: () {
        // Закрываем диалог перед открытием ссылки для лучшего UX
        Navigator.pop(context); 
        _launchUrl(url);
      },
    );
  }
}
