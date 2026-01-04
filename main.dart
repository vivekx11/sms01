// main.dart - Complete Mobile Repair Shop Manager (All-in-One) - FIXED
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:excel/excel.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:telephony/telephony.dart';
import 'package:file_picker/file_picker.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final db = await AppDatabase.init();

  runApp(
    MultiProvider(
      providers: [ChangeNotifierProvider(create: (_) => AppState(db))],
      child: MyRepairShopApp(),
    ),
  );
}

class MyRepairShopApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Mobile Repair All-in-One',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(primarySwatch: Colors.deepPurple, useMaterial3: true),
      home: MainHomeScreen(),
    );
  }
}

/////////////////////
// App State & DB  //
/////////////////////

class AppState extends ChangeNotifier {
  final AppDatabase db;
  List<RepairJob> repairs = [];
  List<SmsLog> smsLogs = [];

  AppState(this.db) {
    _loadAll();
  }

  Future<void> _loadAll() async {
    repairs = await db.getRepairs();
    smsLogs = await db.getSmsLogs();
    notifyListeners();
  }

  Future<void> addRepair(RepairJob r) async {
    await db.insertRepair(r);
    repairs = await db.getRepairs();
    notifyListeners();
  }

  Future<void> addSmsLog(SmsLog s) async {
    await db.insertSmsLog(s);
    smsLogs = await db.getSmsLogs();
    notifyListeners();
  }
}

// Database wrapper
class AppDatabase {
  static Database? _db;

  Database get db {
    if (_db == null) throw Exception("Database not initialized!");
    return _db!;
  }

  static Future<AppDatabase> init() async {
    final instance = AppDatabase();
    await instance._initDb();
    return instance;
  }

  Future<void> _initDb() async {
    Directory documentsDirectory = await getApplicationDocumentsDirectory();
    String path = p.join(documentsDirectory.path, "app_data.db");

    _db = await openDatabase(path, version: 1, onCreate: _onCreate);
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE repairs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        customerName TEXT,
        phone TEXT,
        model TEXT,
        imei TEXT,
        problem TEXT,
        status TEXT,
        imagePath TEXT,
        createdAt INTEGER
      );
    ''');

    await db.execute('''
      CREATE TABLE sms_logs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        toNumber TEXT,
        message TEXT,
        sentAt INTEGER,
        status TEXT
      );
    ''');
  }

  Future<int> insertRepair(RepairJob r) => _db!.insert('repairs', r.toMap());
  Future<List<RepairJob>> getRepairs() async {
    final rows = await _db!.query('repairs', orderBy: 'createdAt DESC');
    return rows.map((r) => RepairJob.fromMap(r)).toList();
  }

  Future<int> insertSmsLog(SmsLog s) => _db!.insert('sms_logs', s.toMap());
  Future<List<SmsLog>> getSmsLogs() async {
    final rows = await _db!.query('sms_logs', orderBy: 'sentAt DESC');
    return rows.map((r) => SmsLog.fromMap(r)).toList();
  }
}

/////////////////////
// Data Models     //
/////////////////////

class RepairJob {
  int? id;
  String customerName;
  String phone;
  String model;
  String imei;
  String problem;
  String status;
  String? imagePath;
  int createdAt;

  RepairJob({
    this.id,
    required this.customerName,
    required this.phone,
    required this.model,
    required this.imei,
    required this.problem,
    this.status = 'Pending',
    this.imagePath,
    int? createdAt,
  }) : createdAt = createdAt ?? DateTime.now().millisecondsSinceEpoch;

  Map<String, dynamic> toMap() => {
        'id': id,
        'customerName': customerName,
        'phone': phone,
        'model': model,
        'imei': imei,
        'problem': problem,
        'status': status,
        'imagePath': imagePath,
        'createdAt': createdAt,
      };

  factory RepairJob.fromMap(Map<String, dynamic> m) => RepairJob(
        id: m['id'],
        customerName: m['customerName'],
        phone: m['phone'],
        model: m['model'],
        imei: m['imei'],
        problem: m['problem'],
        status: m['status'],
        imagePath: m['imagePath'],
        createdAt: m['createdAt'],
      );
}

class SmsLog {
  int? id;
  String toNumber;
  String message;
  int sentAt;
  String status;

  SmsLog({
    this.id,
    required this.toNumber,
    required this.message,
    int? sentAt,
    this.status = 'sent',
  }) : sentAt = sentAt ?? DateTime.now().millisecondsSinceEpoch;

  Map<String, dynamic> toMap() => {
        'id': id,
        'toNumber': toNumber,
        'message': message,
        'sentAt': sentAt,
        'status': status,
      };

  factory SmsLog.fromMap(Map<String, dynamic> m) => SmsLog(
        id: m['id'],
        toNumber: m['toNumber'],
        message: m['message'],
        sentAt: m['sentAt'],
        status: m['status'] ?? 'sent',
      );
}

class Customer {
  int? id;
  String name;
  String phone;
  String address;
  String note;

  Customer({
    this.id,
    required this.name,
    required this.phone,
    this.address = '',
    this.note = '',
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'phone': phone,
        'address': address,
        'note': note,
      };

  factory Customer.fromMap(Map<String, dynamic> m) => Customer(
        id: m['id'],
        name: m['name'],
        phone: m['phone'],
        address: m['address'] ?? '',
        note: m['note'] ?? '',
      );
}

/////////////////////
// Utility         //
/////////////////////

final telephony = Telephony.instance;
final ImagePicker _picker = ImagePicker();

Future<String?> pickImageAndSave() async {
  final xfile = await _picker.pickImage(
    source: ImageSource.camera,
    imageQuality: 70,
  );
  if (xfile == null) return null;

  final doc = await getApplicationDocumentsDirectory();
  final newDir = Directory(p.join(doc.path, 'images'));
  if (!await newDir.exists()) await newDir.create(recursive: true);

  final saved = await File(xfile.path).copy(p.join(newDir.path, p.basename(xfile.path)));

  return saved.path;
}

Future<Uint8List> generateInvoicePdf(RepairJob job, Customer cust) async {
  final pdf = pw.Document();
  pdf.addPage(
    pw.Page(
      build: (pw.Context ctx) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text('Repair Invoice', style: pw.TextStyle(fontSize: 24)),
          pw.SizedBox(height: 10),
          pw.Text('Customer: ${cust.name}'),
          pw.Text('Phone: ${job.phone}'),
          pw.Text('Model: ${job.model}'),
          pw.SizedBox(height: 10),
          pw.Text('Problem: ${job.problem}'),
          pw.SizedBox(height: 20),
          pw.Text('Thank you for your business.'),
        ],
      ),
    ),
  );
  return pdf.save();
}

//////////////////////////////
// UI - Main Screen         //
//////////////////////////////

class MainHomeScreen extends StatefulWidget {
  @override
  _MainHomeScreenState createState() => _MainHomeScreenState();
}

class _MainHomeScreenState extends State<MainHomeScreen> {
  int _selectedIndex = 0;

  final List<Widget> _pages = [
    DashboardPage(),
    RepairTrackingPage(),
    SmsSenderPage(),
    PasswordStorePage(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Mobile Repair Shop Manager")),
      drawer: AppDrawer(
        onNavigate: (index) {
          setState(() => _selectedIndex = index);
          Navigator.pop(context);
        },
      ),
      body: _pages[_selectedIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        selectedItemColor: Colors.deepPurple,
        unselectedItemColor: Colors.grey,
        onTap: (index) => setState(() => _selectedIndex = index),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.dashboard), label: "Home"),
          BottomNavigationBarItem(icon: Icon(Icons.build), label: "Repair"),
          BottomNavigationBarItem(icon: Icon(Icons.sms), label: "SMS"),
          BottomNavigationBarItem(icon: Icon(Icons.lock), label: "Password"),
        ],
      ),
    );
  }
}

class AppDrawer extends StatelessWidget {
  final void Function(int) onNavigate;
  const AppDrawer({Key? key, required this.onNavigate}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: ListView(
        children: [
          const DrawerHeader(
            decoration: BoxDecoration(color: Colors.deepPurple),
            child: Text(
              "All In One Shop Manager",
              style: TextStyle(color: Colors.white, fontSize: 22),
            ),
          ),
          _dItem("Dashboard", 0),
          _dItem("Repair Tracking", 1),
          _dItem("SMS Sender", 2),
          _dItem("Password Store", 3),
          const Divider(),
          ListTile(
            title: const Text("Billing / Invoice"),
            leading: const Icon(Icons.receipt_long),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => BillingPage()),
            ),
          ),
          ListTile(
            title: const Text("Analytics"),
            leading: const Icon(Icons.bar_chart),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => AnalyticsPage()),
            ),
          ),
          ListTile(
            title: const Text("Settings"),
            leading: const Icon(Icons.settings),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => SettingsPage()),
            ),
          ),
        ],
      ),
    );
  }

  ListTile _dItem(String title, int idx) {
    return ListTile(
      title: Text(title),
      leading: const Icon(Icons.arrow_right),
      onTap: () => onNavigate(idx),
    );
  }
}

class BillingPage extends StatelessWidget {
  const BillingPage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final st = Provider.of<AppState>(context, listen: false);

    return Scaffold(
      appBar: AppBar(title: const Text("Billing / Invoice")),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            const Text(
              "Open a repair and use the popup menu -> Invoice to create a PDF invoice.",
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: () async {
                final repairs = await st.db.getRepairs();
                if (repairs.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('No repair found')),
                  );
                  return;
                }

                final last = repairs.first;
                final cust = Customer(
                  name: last.customerName,
                  phone: last.phone,
                );
                final bytes = await generateInvoicePdf(last, cust);
                await Printing.layoutPdf(onLayout: (_) => bytes);
              },
              icon: const Icon(Icons.picture_as_pdf),
              label: const Text('Generate PDF for last repair'),
            ),
          ],
        ),
      ),
    );
  }
}

class AnalyticsPage extends StatelessWidget {
  const AnalyticsPage({Key? key}) : super(key: key);
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Analytics')),
      body: const Padding(
        padding: EdgeInsets.all(12),
        child: Column(
          children: [
            Text('Income: ₹0.00 • Expense: ₹0.00'),
            SizedBox(height: 12),
            SizedBox(height: 200, child: Text('Chart placeholder')),
          ],
        ),
      ),
    );
  }
}

class SettingsPage extends StatelessWidget {
  const SettingsPage({Key? key}) : super(key: key);
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Settings")), // FIXED: AppAppBar -> AppBar
      body: const Center(child: Text("Settings Page")),
    );
  }
}

//////////////////////////////
// Dashboard Page           //
//////////////////////////////

class DashboardPage extends StatelessWidget {
  const DashboardPage({Key? key}) : super(key: key);
  @override
  Widget build(BuildContext context) {
    final st = Provider.of<AppState>(context);
    final pendingRepairs = st.repairs
        .where((r) => r.status != 'Completed')
        .length;
    final completed = st.repairs.where((r) => r.status == 'Completed').length;
    return Padding(
      padding: const EdgeInsets.all(12.0),
      child: ListView(
        children: [
          Card(
            child: ListTile(
              leading: const Icon(Icons.build_circle),
              title: const Text("Repairs Pending"),
              subtitle: Text("$pendingRepairs pending"),
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.check_circle),
              title: const Text("Repairs Completed"),
              subtitle: Text("$completed completed"),
            ),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}

//////////////////////////////
// Repair Tracking Page     //
//////////////////////////////

class RepairTrackingPage extends StatefulWidget {
  const RepairTrackingPage({Key? key}) : super(key: key);
  @override
  State<RepairTrackingPage> createState() => _RepairTrackingPageState();
}

class _RepairTrackingPageState extends State<RepairTrackingPage> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _cname = TextEditingController();
  final TextEditingController _phone = TextEditingController();
  final TextEditingController _model = TextEditingController();
  final TextEditingController _imei = TextEditingController();
  final TextEditingController _problem = TextEditingController();
  String? _imagePath;

  @override
  Widget build(BuildContext context) {
    final st = Provider.of<AppState>(context);
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Form(
            key: _formKey,
            child: Column(
              children: [
                TextFormField(
                  controller: _cname,
                  decoration: const InputDecoration(labelText: 'Customer Name'),
                ),
                TextFormField(
                  controller: _phone,
                  decoration: const InputDecoration(labelText: 'Phone'),
                  keyboardType: TextInputType.phone,
                ),
                TextFormField(
                  controller: _model,
                  decoration: const InputDecoration(labelText: 'Model'),
                ),
                TextFormField(
                  controller: _imei,
                  decoration: const InputDecoration(labelText: 'IMEI'),
                ),
                TextFormField(
                  controller: _problem,
                  decoration: const InputDecoration(labelText: 'Problem'),
                ),
                const SizedBox(height: 8),
                if (_imagePath != null)
                  Image.file(File(_imagePath!), height: 120),
                Row(
                  children: [
                    ElevatedButton.icon(
                      onPressed: () async {
                        final p = await pickImageAndSave();
                        if (p != null) setState(() => _imagePath = p);
                      },
                      icon: const Icon(Icons.camera_alt),
                      label: const Text("Add Photo"),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      onPressed: () async {
                        if (_cname.text.trim().isEmpty ||
                            _phone.text.trim().isEmpty)
                          return;
                        final job = RepairJob(
                          customerName: _cname.text.trim(),
                          phone: _phone.text.trim(),
                          model: _model.text.trim(),
                          imei: _imei.text.trim(),
                          problem: _problem.text.trim(),
                          imagePath: _imagePath,
                        );
                        await st.addRepair(job);
                        _cname.clear();
                        _phone.clear();
                        _model.clear();
                        _imei.clear();
                        _problem.clear();
                        setState(() => _imagePath = null);
                      },
                      icon: const Icon(Icons.save),
                      label: const Text("Save Repair"),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Divider(),
          const SizedBox(height: 8),
          Expanded(
            child: ListView.builder(
              itemCount: st.repairs.length,
              itemBuilder: (_, idx) {
                final r = st.repairs[idx];
                return Card(
                  child: ListTile(
                    leading: r.imagePath != null
                        ? Image.file(
                            File(r.imagePath!),
                            width: 48,
                            height: 48,
                            fit: BoxFit.cover,
                          )
                        : const Icon(Icons.phone_android),
                    title: Text("${r.customerName} • ${r.model}"),
                    subtitle: Text("${r.problem}\nStatus: ${r.status}"),
                    isThreeLine: true,
                    trailing: PopupMenuButton<String>(
                      onSelected: (v) async {
                        if (v == 'Complete') {
                          r.status = 'Completed';
                          await st.db.db.update(
                            'repairs',
                            r.toMap(),
                            where: 'id=?',
                            whereArgs: [r.id],
                          );
                          st.repairs = await st.db.getRepairs();
                          st.notifyListeners();
                        } else if (v == 'Invoice') {
                          final cust = Customer(
                            name: r.customerName,
                            phone: r.phone,
                          );
                          final bytes = await generateInvoicePdf(r, cust);
                          await Printing.layoutPdf(onLayout: (_) => bytes);
                        } else if (v == 'Call') {
                          final uri = Uri.parse('tel:${r.phone}');
                          if (await canLaunchUrl(uri)) await launchUrl(uri);
                        }
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(
                          value: 'Complete',
                          child: Text('Mark Complete'),
                        ),
                        PopupMenuItem(
                          value: 'Invoice',
                          child: Text('Generate Invoice'),
                        ),
                        PopupMenuItem(
                          value: 'Call',
                          child: Text('Call Customer'),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _cname.dispose();
    _phone.dispose();
    _model.dispose();
    _imei.dispose();
    _problem.dispose();
    super.dispose();
  }
}

//////////////////////////////
// SMS Sender Page          //
//////////////////////////////

class SmsSenderPage extends StatefulWidget {
  const SmsSenderPage({Key? key}) : super(key: key);
  @override
  State<SmsSenderPage> createState() => _SmsSenderPageState();
}

class _SmsSenderPageState extends State<SmsSenderPage> {
  final _to = TextEditingController();
  final _msg = TextEditingController();
  bool _sending = false;

  Future<void> _sendSms(AppState st) async {
    final to = _to.text.trim();
    final message = _msg.text.trim();
    if (to.isEmpty || message.isEmpty) return;
    setState(() => _sending = true);
    final permissionsGranted = await telephony.requestPhoneAndSmsPermissions;
    if (permissionsGranted != true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("SMS permission denied")),
      );
      setState(() => _sending = false);
      return;
    }
    try {
      await telephony.sendSms(to: to, message: message);
      final log = SmsLog(toNumber: to, message: message, status: 'sent');
      await st.addSmsLog(log);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("SMS sent")),
      );
      _to.clear();
      _msg.clear();
    } catch (e) {
      final log = SmsLog(toNumber: to, message: message, status: 'failed');
      await st.addSmsLog(log);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Failed to send: $e")),
      );
    } finally {
      setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final st = Provider.of<AppState>(context);
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          TextField(
            controller: _to,
            decoration: const InputDecoration(labelText: 'Recipient (+91...)'),
            keyboardType: TextInputType.phone,
          ),
          TextField(
            controller: _msg,
            decoration: const InputDecoration(labelText: 'Message'),
            maxLines: 4,
          ),
          const SizedBox(height: 8),
          ElevatedButton.icon(
            onPressed: _sending ? null : () => _sendSms(st),
            icon: const Icon(Icons.send),
            label: const Text('Send SMS'),
          ),
          const SizedBox(height: 12),
          const Divider(),
          const SizedBox(height: 12),
          const Text(
            "SMS History",
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: st.smsLogs.length,
              itemBuilder: (_, idx) {
                final s = st.smsLogs[idx];
                return ListTile(
                  title: Text(s.toNumber),
                  subtitle: Text(
                    "${s.message}\n${DateTime.fromMillisecondsSinceEpoch(s.sentAt)}",
                  ),
                  trailing: Text(s.status),
                  isThreeLine: true,
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _to.dispose();
    _msg.dispose();
    super.dispose();
  }
}

//////////////////////////////
// Password Store Page      //
//////////////////////////////

class PasswordStorePage extends StatefulWidget {
  const PasswordStorePage({Key? key}) : super(key: key);
  @override
  State<PasswordStorePage> createState() => _PasswordStorePageState();
}

class _PasswordStorePageState extends State<PasswordStorePage> {
  final _keyCtrl = TextEditingController();
  final _valueCtrl = TextEditingController();
  final secureStorage = FlutterSecureStorage();
  List<MapEntry<String, String>> entries = [];

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    final all = await secureStorage.readAll();
    setState(
      () => entries = all.entries
          .map((e) => MapEntry(e.key, e.value ?? ''))
          .toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Password Store')),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            TextField(
              controller: _keyCtrl,
              decoration: const InputDecoration(
                labelText: 'Label (eg: Google account)',
              ),
            ),
            TextField(
              controller: _valueCtrl,
              decoration: const InputDecoration(labelText: 'Password / PIN'),
              obscureText: true,
            ),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: () async {
                if (_keyCtrl.text.trim().isEmpty ||
                    _valueCtrl.text.trim().isEmpty)
                  return;
                await secureStorage.write(
                  key: _keyCtrl.text.trim(),
                  value: _valueCtrl.text.trim(),
                );
                _keyCtrl.clear();
                _valueCtrl.clear();
                await _loadAll();
              },
              child: const Text('Save'),
            ),
            const Divider(),
            Expanded(
              child: ListView.builder(
                itemCount: entries.length,
                itemBuilder: (_, idx) {
                  final e = entries[idx];
                  return ListTile(
                    title: Text(e.key),
                    subtitle: Text(e.value),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete),
                      onPressed: () async {
                        await secureStorage.delete(key: e.key);
                        await _loadAll();
                      },
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _keyCtrl.dispose();
    _valueCtrl.dispose();
    super.dispose();
  }
}
