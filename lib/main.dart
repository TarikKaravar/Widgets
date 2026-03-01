import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:google_fonts/google_fonts.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Türkçe tarih verilerini başlat
  await initializeDateFormatting('tr_TR', null);

  // Pencere yöneticisini başlat
  await windowManager.ensureInitialized();

  WindowOptions windowOptions = const WindowOptions(
    size: Size(320, 480),
    center: true,
    backgroundColor: Colors.transparent, // Şeffaf arka plan
    skipTaskbar: true, // Görev çubuğunda gizle
    titleBarStyle: TitleBarStyle.hidden, // Çerçevesiz
    alwaysOnTop: false, // Diğer pencerelerin altında kalabilir
  );

  windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.setAsFrameless();
    await windowManager.setHasShadow(false);
    await windowManager.show();
    await windowManager.focus();
  });

  runApp(const DesktopWidgetApp());
}

class DesktopWidgetApp extends StatelessWidget {
  const DesktopWidgetApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        textTheme: GoogleFonts.montserratTextTheme(ThemeData.dark().textTheme),
      ),
      home: const WidgetHome(),
    );
  }
}

class WidgetHome extends StatefulWidget {
  const WidgetHome({super.key});

  @override
  State<WidgetHome> createState() => _WidgetHomeState();
}

class _WidgetHomeState extends State<WidgetHome> {
  DateTime _currentTime = DateTime.now();
  Timer? _timer;
  Map<String, dynamic> _prayerTimes = {};
  bool _isLoading = true;
  String _nextPrayerText = "Hesaplanıyor...";

  final String _city = "Istanbul";
  final String _country = "Turkey";

  // Hangi günde olduğumuzu takip etmek için (Gece yarısı güncellemesi için)
  int _currentDay = DateTime.now().day;

  // Namaz vakitlerinin Türkçe karşılıkları
  final Map<String, String> _prayerNamesTr = {
    'Fajr': 'İmsak',
    'Sunrise': 'Güneş',
    'Dhuhr': 'Öğle',
    'Asr': 'İkindi',
    'Maghrib': 'Akşam',
    'Isha': 'Yatsı',
  };

  @override
  void initState() {
    super.initState();
    _startClock();
    _fetchPrayerTimes();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startClock() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      final now = DateTime.now();
      
      // Eğer bilgisayarın saati yeni bir güne geçtiyse verileri yenile
      if (now.day != _currentDay) {
        _currentDay = now.day;
        _fetchPrayerTimes();
      }

      setState(() {
        _currentTime = now;
        _calculateNextPrayer();
      });
    });
  }

  Future<void> _fetchPrayerTimes() async {
    // Diyanet metodolojisi için method=13
    final url = Uri.parse(
        'https://api.aladhan.com/v1/timingsByCity?city=$_city&country=$_country&method=13');
    try {
      // 10 saniye içinde cevap gelmezse beklemeyi bırakır (bilgisayar ilk açıldığında donmaması için)
      final response = await http.get(url).timeout(const Duration(seconds: 10));
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          _prayerTimes = data['data']['timings'];
          _isLoading = false;
        });
        _calculateNextPrayer();
      }
    } catch (e) {
      debugPrint("API veya İnternet Hatası: $e");
      // Eğer internet yoksa ve hata verirse 10 saniye sonra tekrar dener
      Future.delayed(const Duration(seconds: 10), () {
        if (mounted) {
          _fetchPrayerTimes();
        }
      });
    }
  }

  void _calculateNextPrayer() {
    if (_prayerTimes.isEmpty) return;

    final now = DateTime.now();
    final format = DateFormat("HH:mm");
    
    // Namaz vakitlerini DateTime objesine çevirme
    Map<String, DateTime> prayerDateTimes = {};
    _prayerTimes.forEach((key, value) {
      if (['Fajr', 'Sunrise', 'Dhuhr', 'Asr', 'Maghrib', 'Isha'].contains(key)) {
        final time = format.parse(value);
        prayerDateTimes[key] = DateTime(
            now.year, now.month, now.day, time.hour, time.minute);
      }
    });

    // Gelecek vakti bulma
    String nextPrayerKey = "Isha"; // Varsayılan
    DateTime? nextPrayerTime;

    // Sırayla kontrol et
    for (var entry in prayerDateTimes.entries) {
      if (entry.value.isAfter(now)) {
        nextPrayerKey = entry.key;
        nextPrayerTime = entry.value;
        break;
      }
    }

    // Eğer tüm vakitler geçtiyse sonraki günün sabah namazını hedef al
    if (nextPrayerTime == null) {
      nextPrayerKey = "Fajr";
      nextPrayerTime = prayerDateTimes["Fajr"]!.add(const Duration(days: 1));
    }

    final diff = nextPrayerTime.difference(now);
    final hours = diff.inHours;
    final minutes = diff.inMinutes.remainder(60);
    
    // Türkçe ismini al
    String trName = _prayerNamesTr[nextPrayerKey] ?? nextPrayerKey;

    setState(() {
      if (hours > 0) {
        _nextPrayerText = "$trName vaktine $hours saat $minutes dk kaldı";
      } else {
        _nextPrayerText = "$trName vaktine $minutes dk kaldı";
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // Gün ve tarih formatları Türkçe (tr_TR) olarak ayarlandı
    String dayText = DateFormat('EEEE', 'tr_TR').format(_currentTime).toUpperCase();
    String dateText = DateFormat('d MMMM yyyy', 'tr_TR').format(_currentTime);
    
    // Saat formatı 24 saatlik sisteme çevrildi
    String timeText = DateFormat('HH:mm').format(_currentTime);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: DragToMoveArea(
        child: Container(
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.65), // Cam/Şeffaf arka plan
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withOpacity(0.1), width: 1),
          ),
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // --- Header (Saat, Gün, Tarih) ---
              Center(
                child: Text(
                  dayText,
                  style: GoogleFonts.montserrat(
                    fontWeight: FontWeight.w300,
                    letterSpacing: 6.0,
                    fontSize: 16,
                    color: Colors.white70,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Center(
                child: Text(
                  dateText,
                  style: GoogleFonts.montserrat(
                    fontWeight: FontWeight.w400,
                    fontSize: 14,
                    color: Colors.white54,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Center(
                child: Text(
                  timeText,
                  style: GoogleFonts.montserrat(
                    fontWeight: FontWeight.w200,
                    fontSize: 48,
                    color: Colors.white,
                  ),
                ),
              ),
              
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 20.0),
                child: Divider(color: Colors.white24, thickness: 1),
              ),

              // --- Sonraki Namaz Vakti Sayacı (Taşma Korumalı) ---
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10.0),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      _nextPrayerText,
                      style: GoogleFonts.montserrat(
                        fontWeight: FontWeight.w500,
                        fontSize: 15,
                        color: Colors.white70,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // --- Namaz Vakitleri Listesi ---
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator(color: Colors.white54))
                    : ListView(
                        physics: const NeverScrollableScrollPhysics(),
                        children: [
                          _buildPrayerRow("İmsak", _prayerTimes['Fajr']),
                          _buildPrayerRow("Güneş", _prayerTimes['Sunrise']),
                          _buildPrayerRow("Öğle", _prayerTimes['Dhuhr']),
                          _buildPrayerRow("İkindi", _prayerTimes['Asr']),
                          _buildPrayerRow("Akşam", _prayerTimes['Maghrib']),
                          _buildPrayerRow("Yatsı", _prayerTimes['Isha']),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPrayerRow(String name, String? time) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            name,
            style: GoogleFonts.montserrat(
              fontWeight: FontWeight.w400,
              fontSize: 15,
              color: Colors.white70,
            ),
          ),
          Text(
            time ?? "--:--",
            style: GoogleFonts.montserrat(
              fontWeight: FontWeight.w500,
              fontSize: 15,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}