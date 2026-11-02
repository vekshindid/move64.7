import 'dart:async';
import 'dart:convert';
import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

void main() { WidgetsFlutterBinding.ensureInitialized(); runApp(const Move64App()); }
const categories = ['Тактика','Расчёт вариантов','Стратегия','Дебют','Эндшпиль','Анализ партий','Игра','Другое'];
const accent = Color(0xFF899EFF);
const bg = Color(0xFF10131B);
const panel = Color(0xFF1B2235);
const softPanel = Color(0xFF171D2C);
const muted = Color(0xFFB4BCD1);
const categoryColors = <String, Color>{
 'Тактика': Color(0xFFFF6B82),
 'Расчёт вариантов': Color(0xFF899EFF),
 'Стратегия': Color(0xFFB49AF7),
 'Дебют': Color(0xFFF4B86A),
 'Эндшпиль': Color(0xFF65C9D0),
 'Анализ партий': Color(0xFFD88CC7),
 'Игра': Color(0xFF81C995),
 'Другое': Color(0xFFB8C2D3),
};
Color colorFor(String category) => categoryColors[category] ?? accent;
String dayKey(DateTime d) => '${d.year.toString().padLeft(4,'0')}-${d.month.toString().padLeft(2,'0')}-${d.day.toString().padLeft(2,'0')}';
const monthsRu=['январь','февраль','март','апрель','май','июнь','июль','август','сентябрь','октябрь','ноябрь','декабрь'];
String monthTitle(DateTime d) => '${monthsRu[d.month-1].toUpperCase()} ${d.year}';
String shortDate(DateTime d) => '${d.day} ${monthsRu[d.month-1]} ${d.year}';
String durationText(int seconds) => '${(seconds ~/ 3600).toString().padLeft(2,'0')}:${((seconds ~/ 60)%60).toString().padLeft(2,'0')}:${(seconds%60).toString().padLeft(2,'0')}';
String newId() => DateTime.now().microsecondsSinceEpoch.toString();

class Exercise {
  Exercise({required this.id,required this.title,required this.category,this.favorite=false,this.archived=false,this.isCustom=false});
  final String id; String title,category; bool favorite,archived,isCustom;
  Map<String,dynamic> toJson()=>{'id':id,'title':title,'category':category,'favorite':favorite,'archived':archived,'isCustom':isCustom};
  factory Exercise.fromJson(Map<String,dynamic> m)=>Exercise(id:m['id'] as String,title:m['title'] as String,category:m['category'] as String,favorite:m['favorite']==true,archived:m['archived']==true,isCustom:m['isCustom']==true);
}
class Training {
  Training({required this.id,required this.exerciseId,required this.title,required this.category,required this.date,required this.plannedMinutes,this.startTime,this.completedAt,this.actualSeconds=0,this.rating=0,this.note='',this.solved,this.correct,this.origin='planned'});
  final String id,exerciseId,title,category,origin; String date; int plannedMinutes,actualSeconds,rating; String? startTime,completedAt; String note; int? solved,correct;
  bool get done=>completedAt!=null;
  Map<String,dynamic> toJson()=>{'id':id,'exerciseId':exerciseId,'title':title,'category':category,'date':date,'plannedMinutes':plannedMinutes,'startTime':startTime,'completedAt':completedAt,'actualSeconds':actualSeconds,'rating':rating,'note':note,'solved':solved,'correct':correct,'origin':origin};
  factory Training.fromJson(Map<String,dynamic> m)=>Training(id:m['id'] as String,exerciseId:m['exerciseId'] as String? ?? '',title:m['title'] as String,category:m['category'] as String,date:m['date'] as String,plannedMinutes:(m['plannedMinutes'] as num).toInt(),startTime:m['startTime'] as String?,completedAt:m['completedAt'] as String?,actualSeconds:(m['actualSeconds'] as num?)?.toInt()??0,rating:(m['rating'] as num?)?.toInt()??0,note:m['note'] as String? ?? '',solved:(m['solved'] as num?)?.toInt(),correct:(m['correct'] as num?)?.toInt(),origin:m['origin'] as String? ?? 'planned');
  Training copyTo(String target)=>Training(id:newId(),exerciseId:exerciseId,title:title,category:category,date:target,plannedMinutes:plannedMinutes,startTime:startTime);
}
class ActiveTimer {
  ActiveTimer({required this.trainingId,required this.accumulated,required this.startedAt});
  String trainingId; int accumulated; String? startedAt;
  bool get running=>startedAt!=null;
  int get seconds=>accumulated+(startedAt==null?0:DateTime.now().difference(DateTime.parse(startedAt!)).inSeconds.clamp(0,2147483647));
  Map<String,dynamic> toJson()=>{'trainingId':trainingId,'accumulated':accumulated,'startedAt':startedAt};
  factory ActiveTimer.fromJson(Map<String,dynamic> m)=>ActiveTimer(trainingId:m['trainingId'] as String,accumulated:(m['accumulated'] as num).toInt(),startedAt:m['startedAt'] as String?);
}

class ReminderService {
  static final plugin = FlutterLocalNotificationsPlugin();
  static bool initialized = false;
  static Future<void> init() async {
    if (initialized) return;
    tzdata.initializeTimeZones();
    await plugin.initialize(const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    ));
    initialized = true;
  }
  static Future<void> permission() async {
    await init();
    await plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
  }
  static int idFor(String id) {
    var h = 0;
    for (final c in id.codeUnits) { h = (h * 31 + c) & 0x7fffffff; }
    return h;
  }
  static Future<void> sync(List<Training> trainings, bool enabled, int leadMinutes) async {
    await init();
    await plugin.cancelAll();
    if (!enabled) return;
    final now = DateTime.now();
    for (final t in trainings) {
      if (t.done || t.startTime == null) continue;
      try {
        final bits = t.startTime!.split(':');
        final day = DateTime.parse(t.date);
        final at = DateTime(day.year, day.month, day.day, int.parse(bits[0]), int.parse(bits[1]))
            .subtract(Duration(minutes: leadMinutes));
        if (!at.isAfter(now)) continue;
        await plugin.zonedSchedule(
          idFor(t.id), 'MOVE64 · Скоро тренировка', t.title,
          tz.TZDateTime.from(at, tz.local),
          const NotificationDetails(android: AndroidNotificationDetails(
            'training_reminders', 'Напоминания о тренировках',
            channelDescription: 'Уведомления перед запланированными тренировками',
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
          )),
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
        );
      } catch (e) { debugPrint('Reminder error: $e'); }
    }
  }
}

class MoveStore extends ChangeNotifier {
  final exercises=<Exercise>[]; final trainings=<Training>[]; ActiveTimer? active;
  bool ready=false; bool remindersEnabled=false; int reminderLead=10;
  Future<void> load() async {
    final p=await SharedPreferences.getInstance();
    remindersEnabled=p.getBool('remindersEnabled')??false;
    reminderLead=p.getInt('reminderLead')??10;
    try {
      for(final x in jsonDecode(p.getString('exercises')??'[]') as List){exercises.add(Exercise.fromJson(Map<String,dynamic>.from(x as Map)));}
      for(final x in jsonDecode(p.getString('trainings')??'[]') as List){trainings.add(Training.fromJson(Map<String,dynamic>.from(x as Map)));}
      final raw=p.getString('active'); if(raw!=null) active=ActiveTimer.fromJson(Map<String,dynamic>.from(jsonDecode(raw) as Map));
    } catch(e){debugPrint('Data read error: $e');}
    if(exercises.isEmpty){final examples=<String,List<String>>{
 'Тактика':['Мат в 1 ход','Мат в 2 хода','Мат в 3 хода','Мат в 4 хода','Защита от мата','Тактическая защита','Поиск единственного хода','Комбинации на выигрыш материала','Расчёт жертв','Комбинации с проходной пешкой','Тактика на последней горизонтали','Разрушение пешечного прикрытия','Мельница','Рентген','Освобождение линии','Перекрытие','Уничтожение защитника','Патовые комбинации','Двойной удар','Связка','Вилка','Вскрытое нападение','Отвлечение','Завлечение','Перегрузка','Промежуточный ход','Жертва качества','Защита от тактических угроз'],
 'Расчёт вариантов':['Расчёт форсированных вариантов','Дерево вариантов','Кандидаты и проверка','Расчёт без передвижения фигур','Визуализация позиции','Слепой расчёт','Промежуточные позиции','Проверка тактических угроз','Поиск опровержений','Тренировка глубины расчёта'],
 'Стратегия':['Пешечные структуры','Слабые поля','Хорошие и плохие фигуры','План в миттельшпиле','Профилактика','Открытые линии','Преимущество двух слонов','Игра против изолированной пешки','Карлсбадская структура','Миноритарная атака','Игра с пространственным перевесом','Блокада проходной пешки','Пешечные прорывы','Разноцветные слоны в миттельшпиле'],
 'Дебют':['Повторение репертуара белыми','Повторение репертуара чёрными','Разбор типовых планов','Проверка вариантов по памяти','Разбор дебютных ошибок','Подготовка к сопернику','Дебютные ловушки','Повторение типовых структур','Тренировка порядка ходов','Переход из дебюта в миттельшпиль'],
 'Эндшпиль':['Король и пешка','Оппозиция','Правило квадрата','Ладейные окончания','Позиция Лусены','Позиция Филидора','Ферзевые окончания','Слоновые окончания','Коневые окончания','Пешечные гонки','Треугольник','Цугцванг','Крепость','Ладья против пешки','Ладья и пешка против ладьи','Техника реализации лишней пешки'],
 'Анализ партий':['Самостоятельный анализ партии','Анализ с движком','Разбор критических моментов','Разбор собственных ошибок','Анализ классической партии','Подготовка выводов','Анализ без движка','Поиск упущенных возможностей','Разбор цейтнота','Проверка дебютной подготовки','Анализ эндшпиля партии'],
 'Игра':['Пуля (Bullet)','Блиц (Blitz)','Рапид (Rapid)','Классика (Classical)','Шахматы Фишера (Chess960)','Тренировочная партия'],
 'Другое':['Чтение шахматной книги','Просмотр лекции','Работа с тренером','Повторение конспекта','Шахматная визуализация','Шахматы вслепую','Решение этюдов','Разбор шахматных задач','Повторение карточек','Работа над концентрацией']};
 for(final entry in examples.entries){for(final title in entry.value){exercises.add(Exercise(id:newId()+'${exercises.length}',title:title,category:entry.key));}}await save();} 
    ready=true;notifyListeners();
    await refreshReminders();
  }
  Future<void> save() async {
    final p=await SharedPreferences.getInstance();
    await p.setString('exercises',jsonEncode(exercises.map((e)=>e.toJson()).toList()));
    await p.setString('trainings',jsonEncode(trainings.map((e)=>e.toJson()).toList()));
    if(active==null){await p.remove('active');}else{await p.setString('active',jsonEncode(active!.toJson()));}
    notifyListeners();
    await refreshReminders();
  }
  Future<void> refreshReminders() async {
    try { await ReminderService.sync(trainings, remindersEnabled, reminderLead); }
    catch(e) { debugPrint('Notifications unavailable: $e'); }
  }
  Future<void> setReminders(bool value) async {
    if(value) await ReminderService.permission();
    remindersEnabled=value;
    final p=await SharedPreferences.getInstance();
    await p.setBool('remindersEnabled', value);
    notifyListeners(); await refreshReminders();
  }
  Future<void> setReminderLead(int minutes) async {
    reminderLead=minutes;
    final p=await SharedPreferences.getInstance();
    await p.setInt('reminderLead', minutes);
    notifyListeners(); await refreshReminders();
  }
  Training? findTraining(String id){for(final t in trainings){if(t.id==id)return t;}return null;}
  Future<void> start(Training t) async {if(active!=null)return;active=ActiveTimer(trainingId:t.id,accumulated:0,startedAt:null);await save();}
  Future<void> togglePause() async {final a=active;if(a==null)return;if(a.running){a.accumulated=a.seconds;a.startedAt=null;}else{a.startedAt=DateTime.now().toIso8601String();}await save();}
  Future<void> cancelTimer() async {active=null;await save();}
  Future<void> finishTimer() async {final a=active;if(a==null)return;final t=findTraining(a.trainingId);if(t!=null){t.actualSeconds=a.seconds;t.completedAt=DateTime.now().toIso8601String();}active=null;await save();}
  Future<void> copyPeriod(DateTime from,DateTime to,{bool week=false}) async {
    final first=week?from.subtract(Duration(days:from.weekday-1)):from;
    final dest=week?to.subtract(Duration(days:to.weekday-1)):to;
    final count=week?7:1;
    final additions=<Training>[];
    for(var i=0;i<count;i++){
      final source=dayKey(first.add(Duration(days:i)));
      final target=dayKey(dest.add(Duration(days:i)));
      for(final t in trainings.where((x)=>x.date==source && x.origin=='planned').toList()){if(source!=target) additions.add(t.copyTo(target));}
    }
    trainings.addAll(additions);await save();
  }
}
class Move64App extends StatefulWidget {const Move64App({super.key});@override State<Move64App> createState()=>_Move64AppState();}
class _Move64AppState extends State<Move64App> {
  final store=MoveStore();
  @override void initState(){super.initState();store.load();}
  @override Widget build(BuildContext context)=>MaterialApp(debugShowCheckedModeBanner:false,title:'MOVE64',locale:const Locale('ru','RU'),supportedLocales:const [Locale('ru','RU')],localizationsDelegates:const [GlobalMaterialLocalizations.delegate,GlobalCupertinoLocalizations.delegate,GlobalWidgetsLocalizations.delegate],theme:ThemeData(pageTransitionsTheme:const PageTransitionsTheme(builders:{TargetPlatform.android:FadeUpwardsPageTransitionsBuilder()}),useMaterial3:true,brightness:Brightness.dark,scaffoldBackgroundColor:bg,colorScheme:ColorScheme.fromSeed(seedColor:accent,brightness:Brightness.dark,surface:panel),appBarTheme:const AppBarTheme(backgroundColor:bg,surfaceTintColor:Colors.transparent,elevation:0,scrolledUnderElevation:0),cardTheme:CardThemeData(color:panel,shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(22))),inputDecorationTheme:InputDecorationTheme(filled:true,fillColor:softPanel,contentPadding:const EdgeInsets.all(18),border:OutlineInputBorder(borderRadius:BorderRadius.circular(18),borderSide:BorderSide.none)),filledButtonTheme:FilledButtonThemeData(style:FilledButton.styleFrom(backgroundColor:accent,foregroundColor:bg)),dialogTheme:DialogThemeData(backgroundColor:const Color(0xFF232A3D),shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(24))),popupMenuTheme:PopupMenuThemeData(color:const Color(0xFF252D40),shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(18)))),home:AnimatedBuilder(animation:store,builder:(context,_)=>store.ready?SplashGate(store:store):const Scaffold(body:Center(child:CircularProgressIndicator()))));
}
class SplashGate extends StatefulWidget {const SplashGate({super.key,required this.store});final MoveStore store;@override State<SplashGate> createState()=>_SplashGateState();}
class _SplashGateState extends State<SplashGate>{bool show=true;@override void initState(){super.initState();Future<void>.delayed(const Duration(milliseconds:1100),(){if(mounted)setState(()=>show=false);});}
 @override Widget build(BuildContext context)=>AnimatedSwitcher(duration:const Duration(milliseconds:460),child:show?Scaffold(key:const ValueKey('splash'),body:Center(child:Column(mainAxisSize:MainAxisSize.min,children:[Container(width:112,height:112,padding:const EdgeInsets.all(22),decoration:BoxDecoration(gradient:const LinearGradient(colors:[Color(0xFF899EFF),Color(0xFF4B5DA5)]),borderRadius:BorderRadius.circular(30)),child:const Icon(Icons.castle_outlined,size:58,color:bg)),const SizedBox(height:24),const Text('MOVE64',style:TextStyle(fontSize:32,fontWeight:FontWeight.w600,letterSpacing:5))]))):HomeShell(key:const ValueKey('home'),store:widget.store));
}
class HomeShell extends StatefulWidget {const HomeShell({super.key,required this.store});final MoveStore store;@override State<HomeShell> createState()=>_HomeShellState();}
class _HomeShellState extends State<HomeShell> {
  int tab=0;DateTime selected=DateTime.now();bool calendar=false;
  Future<void> addTraining() async {
    final e=await Navigator.push<Exercise>(context,MaterialPageRoute(builder:(_)=>CatalogScreen(store:widget.store,pick:true)));
    if(!mounted||e==null)return;
    final t=await Navigator.push<Training>(context,MaterialPageRoute(builder:(_)=>TrainingEditor(exercise:e,date:selected)));
    if(!mounted||t==null)return;
    widget.store.trainings.add(t);await widget.store.save();
  }
  void openTimer(){Navigator.push(context,MaterialPageRoute(builder:(_)=>TimerScreen(store:widget.store)));}
  @override Widget build(BuildContext context){
    final pages=[_dayPage(),DiaryScreen(store:widget.store),StatsScreen(store:widget.store),CatalogScreen(store:widget.store,embedded:true)];
    return Scaffold(
      extendBody:false,
      appBar:AppBar(title:const Text('MOVE64',style:TextStyle(fontWeight:FontWeight.w600,letterSpacing:3)),
        actions:tab==0?[IconButton(tooltip:'Настройки',onPressed:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>Scaffold(appBar:AppBar(title:const Text('Настройки')),body:SettingsScreen(store:widget.store)))),icon:const Icon(Icons.settings_outlined))]:null),
      body:Column(children:[if(widget.store.active!=null)MaterialBanner(content:Text('Таймер: ${widget.store.findTraining(widget.store.active!.trainingId)?.title??''}'),actions:[TextButton(onPressed:openTimer,child:const Text('Открыть'))]),Expanded(child:pages[tab])]),
      bottomNavigationBar:SafeArea(top:false,child:Padding(padding:const EdgeInsets.fromLTRB(16,4,16,8),child:ClipRRect(borderRadius:BorderRadius.circular(28),child:BackdropFilter(filter:ImageFilter.blur(sigmaX:26,sigmaY:26),child:Container(height:76,decoration:BoxDecoration(gradient:const LinearGradient(colors:[Color(0xED252B3B),Color(0xE71B2337)]),borderRadius:BorderRadius.circular(28),border:Border.all(color:Colors.white.withValues(alpha:.08))),child:Row(children:[for(var i=0;i<4;i++)Expanded(child:InkWell(onTap:()=>setState(()=>tab=i),child:AnimatedContainer(duration:const Duration(milliseconds:240),margin:const EdgeInsets.symmetric(horizontal:2,vertical:4),decoration:BoxDecoration(gradient:i==tab?RadialGradient(radius:1.0,colors:[accent.withValues(alpha:.24),Colors.transparent]):null,borderRadius:BorderRadius.circular(20)),child:Column(mainAxisAlignment:MainAxisAlignment.center,children:[Icon([Icons.home_outlined,Icons.menu_book_outlined,Icons.show_chart_outlined,Icons.grid_view_outlined][i],size:24,color:i==tab?accent:muted),const SizedBox(height:6),Text(['Главная','Дневник','Статистика','Каталог'][i],style:TextStyle(fontSize:11,fontWeight:i==tab?FontWeight.w600:FontWeight.w400,color:i==tab?accent:muted))]))))])))))),
    );
  }
  Widget _dayPage(){
    final start=selected.subtract(Duration(days:selected.weekday-1));
    final items=widget.store.trainings.where((t)=>t.date==dayKey(selected)).toList()..sort((a,b){if(a.done!=b.done)return a.done?1:-1;return (a.startTime??'99:99').compareTo(b.startTime??'99:99');});
    final completed=items.where((x)=>x.done).length;
    final today=dayKey(selected)==dayKey(DateTime.now());
    final future=dayKey(selected).compareTo(dayKey(DateTime.now()))>0;
    return Column(children:[Expanded(child:ListView(padding:const EdgeInsets.fromLTRB(18,18,18,28),children:[
      Row(children:[Expanded(child:InkWell(onTap:() async {final picked=await showDatePicker(context:context,initialDate:selected,firstDate:DateTime(2020),lastDate:DateTime(2100),initialDatePickerMode:DatePickerMode.year);if(picked!=null&&mounted)setState(()=>selected=picked);},borderRadius:BorderRadius.circular(12),child:Padding(padding:const EdgeInsets.symmetric(vertical:8),child:Row(mainAxisSize:MainAxisSize.min,children:[Flexible(child:Text(monthTitle(selected),style:const TextStyle(fontSize:25,fontWeight:FontWeight.w600,letterSpacing:-.7))),const SizedBox(width:7),const Icon(Icons.keyboard_arrow_down_rounded,size:20,color:muted)])))),TextButton(onPressed:()=>setState(()=>selected=DateTime.now()),child:const Text('Сегодня'))]),
      const SizedBox(height:14),
      AnimatedSwitcher(duration:const Duration(milliseconds:300),switchInCurve:Curves.easeOutCubic,child:calendar?
        Column(key:const ValueKey('month'),children:[_monthCalendar(),IconButton(tooltip:'Свернуть календарь',onPressed:()=>setState(()=>calendar=false),icon:const Icon(Icons.keyboard_arrow_up_rounded))]):
        Column(key:const ValueKey('week'),children:[GestureDetector(behavior:HitTestBehavior.opaque,onHorizontalDragEnd:(details){final velocity=details.primaryVelocity??0;if(velocity.abs()<120)return;setState(()=>selected=selected.add(Duration(days:velocity<0?7:-7)));},child:Row(children:List.generate(7,(i){final d=start.add(Duration(days:i));return Expanded(child:_dayChip(d));}))),IconButton(tooltip:'Раскрыть календарь',onPressed:()=>setState(()=>calendar=true),icon:const Icon(Icons.keyboard_arrow_down_rounded))])),
      const SizedBox(height:14),
      Row(children:[Expanded(child:_planAction('Добавить тренировку',Icons.add,addTraining,primary:true)),const SizedBox(width:8),Expanded(child:_planAction('Копировать день',Icons.copy_outlined,()=>_copy(false))),const SizedBox(width:8),Expanded(child:_planAction('Копировать неделю',Icons.calendar_today_outlined,()=>_copy(true)))]),
      const SizedBox(height:22),
      Row(children:[Expanded(child:Text(today?'План на сегодня':'План на ${selected.day} ${monthsRu[selected.month-1]}',style:const TextStyle(fontSize:19,fontWeight:FontWeight.w600))),if(items.isNotEmpty)Text('$completed / ${items.length}',style:const TextStyle(color:muted))]),
      if(items.isNotEmpty)...[const SizedBox(height:12),ClipRRect(borderRadius:BorderRadius.circular(10),child:LinearProgressIndicator(value:completed/items.length,minHeight:5,backgroundColor:panel,valueColor:const AlwaysStoppedAnimation(accent)))],
      const SizedBox(height:20),
      if(items.isEmpty)Container(padding:const EdgeInsets.symmetric(horizontal:24,vertical:40),decoration:BoxDecoration(gradient:const LinearGradient(begin:Alignment.topLeft,end:Alignment.bottomRight,colors:[Color(0xFF283251),Color(0xFF1B2235),Color(0xFF25243F)]),borderRadius:BorderRadius.circular(26)),child:Column(children:[const Icon(Icons.event_note_outlined,size:40,color:accent),const SizedBox(height:18),const Text('Нет запланированных тренировок',style:TextStyle(fontSize:18,fontWeight:FontWeight.w600),textAlign:TextAlign.center),const SizedBox(height:8),Text(future?'Можно составить план на этот день.':'Добавьте упражнение или скопируйте готовый план.',textAlign:TextAlign.center,style:const TextStyle(color:muted))])),
      if(items.isNotEmpty && completed==items.length)Padding(padding:const EdgeInsets.only(bottom:12),child:Row(children:[const Icon(Icons.check_circle_outline,color:muted),const SizedBox(width:12),const Expanded(child:Text('Все тренировки завершены'))])),
      for(final t in items)TrainingTile(t:t,store:widget.store,onStart:openTimer),
    ])),

    ]);
  }
  Widget _planAction(String label,IconData icon,VoidCallback action,{bool primary=false})=>Material(color:Colors.transparent,child:InkWell(onTap:action,borderRadius:BorderRadius.circular(18),child:Container(height:74,padding:const EdgeInsets.symmetric(horizontal:5,vertical:9),decoration:BoxDecoration(gradient:primary?const LinearGradient(colors:[Color(0xFF899EFF),Color(0xFF667CE0)]):const LinearGradient(colors:[Color(0xFF222A3D),Color(0xFF1B2234)]),borderRadius:BorderRadius.circular(18),border:primary?null:Border.all(color:Colors.white.withValues(alpha:.08))),child:Column(mainAxisAlignment:MainAxisAlignment.center,children:[Icon(icon,size:20,color:primary?bg:accent),const SizedBox(height:5),Text(label,textAlign:TextAlign.center,maxLines:2,style:TextStyle(fontSize:11,height:1.1,fontWeight:FontWeight.w500,color:primary?bg:Colors.white))]))));
  Widget _dayChip(DateTime d){
    final key=dayKey(d);final chosen=key==dayKey(selected);final today=key==dayKey(DateTime.now());
    final count=widget.store.trainings.where((t)=>t.date==key).length;
    return InkWell(onTap:()=>setState(()=>selected=d),borderRadius:BorderRadius.circular(18),child:AnimatedContainer(duration:const Duration(milliseconds:220),margin:const EdgeInsets.symmetric(horizontal:2),padding:const EdgeInsets.symmetric(vertical:13),height:86,decoration:BoxDecoration(color:chosen?accent:count>0?const Color(0xFF2A3450):softPanel,borderRadius:BorderRadius.circular(18),border:today&&!chosen?Border.all(color:accent,width:1):null),child:Column(mainAxisAlignment:MainAxisAlignment.center,children:[Text(['Пн','Вт','Ср','Чт','Пт','Сб','Вс'][d.weekday-1],style:TextStyle(fontSize:11,color:chosen?bg:muted)),const SizedBox(height:7),Text('${d.day}',style:TextStyle(fontSize:17,fontWeight:FontWeight.w700,color:chosen?bg:Colors.white)),const SizedBox(height:8),SizedBox(height:5,child:Wrap(alignment:WrapAlignment.center,spacing:2,children:List.generate(count.clamp(0,6),(i)=>Container(width:3,height:3,decoration:BoxDecoration(shape:BoxShape.circle,color:chosen?bg:accent)))))])));
  }
  Widget _monthCalendar(){
    final first=DateTime(selected.year,selected.month,1);final days=DateTime(selected.year,selected.month+1,0).day;
    final offset=first.weekday-1;
    return Column(children:[Row(children:[for(final day in ['Пн','Вт','Ср','Чт','Пт','Сб','Вс'])Expanded(child:Center(child:Text(day,style:TextStyle(color:muted))))]),const SizedBox(height:12),for(var row=0;row<((offset+days+6)~/7);row++)Padding(padding:const EdgeInsets.only(bottom:7),child:Row(children:[for(var col=0;col<7;col++)Expanded(child:Builder(builder:(context){final n=row*7+col-offset+1;if(n<1||n>days)return const SizedBox(height:52);final d=DateTime(selected.year,selected.month,n);final key=dayKey(d);final chosen=key==dayKey(selected);final today=key==dayKey(DateTime.now());final count=widget.store.trainings.where((t)=>t.date==key).length;return InkWell(onTap:()=>setState(()=>selected=d),borderRadius:BorderRadius.circular(18),child:Container(height:52,margin:const EdgeInsets.symmetric(horizontal:3),decoration:BoxDecoration(color:chosen?accent:count>0?const Color(0xFF2A3450):Colors.transparent,borderRadius:BorderRadius.circular(16),border:today?Border.all(color:chosen?Colors.white:accent):null),child:Column(mainAxisAlignment:MainAxisAlignment.center,children:[Text('$n',style:TextStyle(color:chosen?bg:Colors.white,fontWeight:chosen?FontWeight.w700:FontWeight.w400)),const SizedBox(height:5),Row(mainAxisAlignment:MainAxisAlignment.center,children:List.generate(count.clamp(0,6),(i)=>Container(width:3,height:3,margin:const EdgeInsets.symmetric(horizontal:1),decoration:BoxDecoration(shape:BoxShape.circle,color:chosen?bg:accent))))])));}))]))]);
  }
  Future<void> _copy(bool week) async {
    final target=await showDatePicker(context:context,initialDate:selected.add(Duration(days:week?7:1)),firstDate:DateTime(2020),lastDate:DateTime(2100));
    if(!mounted||target==null)return;
    final yes=await showDialog<bool>(context:context,builder:(c)=>AlertDialog(title:Text(week?'Копировать неделю?':'Копировать день?'),content:Text('Новые занятия будут добавлены к существующим в периоде назначения (${shortDate(target)}). Результаты не копируются.'),actions:[TextButton(onPressed:()=>Navigator.pop(c,false),child:const Text('Отмена')),FilledButton(onPressed:()=>Navigator.pop(c,true),child:const Text('Копировать'))]));
    if(yes==true){await widget.store.copyPeriod(selected,target,week:week);if(mounted)setState(()=>selected=target);}
  }
}
const categoryIcons=<String,IconData>{
 'Тактика':Icons.bolt_outlined,'Расчёт вариантов':Icons.account_tree_outlined,'Стратегия':Icons.psychology_outlined,'Дебют':Icons.auto_stories_outlined,'Эндшпиль':Icons.flag_outlined,'Анализ партий':Icons.analytics_outlined,'Игра':Icons.sports_esports_outlined,'Другое':Icons.widgets_outlined,
};
class CatalogScreen extends StatefulWidget {const CatalogScreen({super.key,required this.store,this.pick=false,this.embedded=false});final MoveStore store;final bool pick,embedded;@override State<CatalogScreen> createState()=>_CatalogScreenState();}
class _CatalogScreenState extends State<CatalogScreen>{String search='';
 Future<void> create() async {
   final title=TextEditingController();String category=categories.first;
   final ok=await showDialog<bool>(context:context,builder:(c)=>StatefulBuilder(builder:(c,update)=>AlertDialog(title:const Text('Новое упражнение'),content:Column(mainAxisSize:MainAxisSize.min,children:[TextField(controller:title,decoration:const InputDecoration(labelText:'Название')),const SizedBox(height:12),DropdownButtonFormField<String>(initialValue:category,items:categories.map((x)=>DropdownMenuItem(value:x,child:Text(x))).toList(),onChanged:(x){if(x!=null)update(()=>category=x);})]),actions:[TextButton(onPressed:()=>Navigator.pop(c,false),child:const Text('Отмена')),FilledButton(onPressed:()=>Navigator.pop(c,true),child:const Text('Создать'))])));
   if(ok==true&&title.text.trim().isNotEmpty){widget.store.exercises.add(Exercise(id:newId(),title:title.text.trim(),category:category,isCustom:true));await widget.store.save();if(mounted)setState((){});}title.dispose();
 }
 @override Widget build(BuildContext context){
   final q=search.toLowerCase().trim();
   final content=Column(children:[Padding(padding:const EdgeInsets.all(16),child:TextField(decoration:const InputDecoration(prefixIcon:Icon(Icons.search),hintText:'Поиск упражнений'),onChanged:(v)=>setState(()=>search=v))),Expanded(child:ListView(children:[_favorites(q),for(final cat in categories) Builder(builder:(context){final list=widget.store.exercises.where((e)=>!e.archived&&e.category==cat&&(q.isEmpty||e.title.toLowerCase().contains(q)||cat.toLowerCase().contains(q))).toList()..sort((a,b)=>a.title.compareTo(b.title));if(list.isEmpty)return const SizedBox.shrink();return Card(margin:const EdgeInsets.fromLTRB(16,0,16,10),child:ExpansionTile(initiallyExpanded:q.isNotEmpty,leading:Icon(categoryIcons[cat],color:colorFor(cat)),title:Text(cat),subtitle:Text('${list.length} упражнений'),children:[for(final e in list)ListTile(title:Text(e.title),onTap:widget.pick?()=>Navigator.pop(context,e):null,leading:IconButton(tooltip:e.favorite?'Убрать из избранного':'В избранное',icon:Icon(e.favorite?Icons.star_rounded:Icons.star_border_rounded,color:e.favorite?accent:Colors.white54),onPressed:()async{setState(()=>e.favorite=!e.favorite);await widget.store.save();}),trailing:widget.pick?const Icon(Icons.chevron_right):(e.isCustom?PopupMenuButton<String>(onSelected:(v)async{if(v=='archive'){setState(()=>e.archived=true);await widget.store.save();}},itemBuilder:(_)=>[const PopupMenuItem(value:'archive',child:Text('Архивировать'))]):null))]));})]))]);
   return widget.embedded?Column(children:[Padding(padding:const EdgeInsets.fromLTRB(18,14,18,0),child:Row(children:[const Expanded(child:Text('Каталог',style:TextStyle(fontSize:27,fontWeight:FontWeight.w600))),IconButton(onPressed:create,icon:const Icon(Icons.add_circle_outline))])),Expanded(child:content)]):Scaffold(appBar:AppBar(title:Text(widget.pick?'Выбрать упражнение':'Каталог упражнений'),actions:[IconButton(tooltip:'Создать упражнение',onPressed:create,icon:const Icon(Icons.add))]),body:content);
 }
 Widget _favorites(String q){final list=widget.store.exercises.where((e)=>!e.archived&&e.favorite&&(q.isEmpty||e.title.toLowerCase().contains(q))).toList();return Card(margin:const EdgeInsets.fromLTRB(16,0,16,10),child:ExpansionTile(initiallyExpanded:true,leading:const Icon(Icons.star_border_outlined,color:accent),title:const Text('Избранное'),subtitle:Text('${list.length} упражнений'),children:list.isEmpty?[const ListTile(title:Text('Пока нет избранных упражнений',style:TextStyle(color:muted)))]:list.map((e)=>ListTile(title:Text(e.title),onTap:widget.pick?()=>Navigator.pop(context,e):null,leading:IconButton(icon:const Icon(Icons.star_outline,color:accent),onPressed:()async{setState(()=>e.favorite=false);await widget.store.save();}),subtitle:Text(e.category))).toList()));}
}
class TrainingEditor extends StatefulWidget {const TrainingEditor({super.key,required this.exercise,required this.date,this.existing});final Exercise exercise;final DateTime date;final Training? existing;@override State<TrainingEditor> createState()=>_TrainingEditorState();}
class _TrainingEditorState extends State<TrainingEditor>{late DateTime date;late TextEditingController minutes;TimeOfDay? time;
  @override void initState(){super.initState();date=widget.existing==null?widget.date:DateTime.parse(widget.existing!.date);minutes=TextEditingController(text:'${widget.existing?.plannedMinutes??30}');final v=widget.existing?.startTime;if(v!=null){final parts=v.split(':');time=TimeOfDay(hour:int.parse(parts[0]),minute:int.parse(parts[1]));}}
  @override void dispose(){minutes.dispose();super.dispose();}
  @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:Text(widget.existing==null?'Добавить тренировку':'Редактировать план')),body:ListView(padding:const EdgeInsets.all(20),children:[Text(widget.exercise.title,style:Theme.of(context).textTheme.headlineSmall),Text(widget.exercise.category),const SizedBox(height:20),ListTile(title:const Text('Дата'),subtitle:Text(shortDate(date)),trailing:const Icon(Icons.calendar_month),onTap:()async{final d=await showDatePicker(context:context,initialDate:date,firstDate:DateTime(2020),lastDate:DateTime(2100));if(d!=null)setState(()=>date=d);}),TextField(controller:minutes,keyboardType:TextInputType.number,decoration:const InputDecoration(labelText:'Плановая длительность (минуты)')),ListTile(title:const Text('Время начала (необязательно)'),subtitle:Text(time?.format(context)??'Не задано'),trailing:IconButton(onPressed:()=>setState(()=>time=null),icon:const Icon(Icons.close)),onTap:()async{final v=await showTimePicker(context:context,initialTime:time??TimeOfDay.now());if(v!=null)setState(()=>time=v);}),const SizedBox(height:24),FilledButton(onPressed:(){final m=int.tryParse(minutes.text);if(m==null||m<=0||m>1440){ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Укажите длительность от 1 до 1440 минут')));return;}final tm=time==null?null:'${time!.hour.toString().padLeft(2,'0')}:${time!.minute.toString().padLeft(2,'0')}';Navigator.pop(context,Training(id:widget.existing?.id??newId(),exerciseId:widget.exercise.id,title:widget.exercise.title,category:widget.exercise.category,date:dayKey(date),plannedMinutes:m,startTime:tm));},child:Text(widget.existing==null?'Добавить тренировку':'Сохранить изменения'))]));
}
class TrainingTile extends StatelessWidget {
 const TrainingTile({super.key,required this.t,required this.store,required this.onStart});
 final Training t;final MoveStore store;final VoidCallback onStart;
 void open(BuildContext context){if(t.done){Navigator.push(context,MaterialPageRoute(builder:(_)=>ResultScreen(store:store,training:t)));}else if(t.date.compareTo(dayKey(DateTime.now()))>0){ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Тренировку будущего дня пока нельзя запустить')));}else if(store.active!=null&&store.active!.trainingId!=t.id){ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Сначала завершите другую тренировку')));}else{Navigator.push(context,MaterialPageRoute(builder:(_)=>TimerScreen(store:store,planned:t)));}}
 @override Widget build(BuildContext context)=>Card(margin:const EdgeInsets.only(bottom:11),child:Padding(padding:const EdgeInsets.symmetric(horizontal:8,vertical:13),child:Row(children:[IconButton(tooltip:t.done?'Результат':'Открыть тренировку',onPressed:()=>open(context),icon:Icon(t.done?Icons.check_circle_outline:Icons.play_circle_outline,color:t.done?muted:accent,size:29)),Icon(categoryIcons[t.category]??Icons.circle_outlined,color:colorFor(t.category),size:23),const SizedBox(width:13),Expanded(child:InkWell(onTap:()=>open(context),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(t.title,style:TextStyle(fontSize:16,fontWeight:FontWeight.w600,color:t.done?muted:Colors.white,decoration:t.done?TextDecoration.lineThrough:null,decorationColor:muted)),const SizedBox(height:5),Text('${t.category} · ${t.plannedMinutes} мин${t.done?' · Выполнено':''}',style:const TextStyle(fontSize:12,color:muted))]))),PopupMenuButton<String>(icon:const Icon(Icons.more_vert_outlined,color:muted),onSelected:(v)async{
   if(v=='copy'){final d=await showDatePicker(context:context,initialDate:DateTime.parse(t.date).add(const Duration(days:1)),firstDate:DateTime(2020),lastDate:DateTime(2100));if(d!=null){store.trainings.add(t.copyTo(dayKey(d)));await store.save();}}
   if(v=='delete'){if(store.active?.trainingId==t.id)return;final yes=await showDialog<bool>(context:context,builder:(c)=>AlertDialog(title:const Text('Удалить тренировку?'),content:const Text('План и связанные результаты будут удалены.'),actions:[TextButton(onPressed:()=>Navigator.pop(c,false),child:const Text('Отмена')),FilledButton(onPressed:()=>Navigator.pop(c,true),child:const Text('Удалить'))]));if(yes==true){store.trainings.remove(t);await store.save();}}
   if(v=='edit'){final ex=Exercise(id:t.exerciseId,title:t.title,category:t.category);if(!context.mounted)return;final updated=await Navigator.push<Training>(context,MaterialPageRoute(builder:(_)=>TrainingEditor(exercise:ex,date:DateTime.parse(t.date),existing:t)));if(updated!=null){t.date=updated.date;t.plannedMinutes=updated.plannedMinutes;t.startTime=updated.startTime;await store.save();}}
 },itemBuilder:(_)=>[const PopupMenuItem(value:'copy',child:Text('Копировать')),if(!t.done&&store.active?.trainingId!=t.id)const PopupMenuItem(value:'edit',child:Text('Изменить / перенести')),if(store.active?.trainingId!=t.id)const PopupMenuItem(value:'delete',child:Text('Удалить'))])])));
}
class TimerScreen extends StatefulWidget {const TimerScreen({super.key,required this.store,this.planned});final MoveStore store;final Training? planned;@override State<TimerScreen> createState()=>_TimerScreenState();}
class _TimerScreenState extends State<TimerScreen>{Timer? ticker;@override void initState(){super.initState();ticker=Timer.periodic(const Duration(seconds:1),(_){if(mounted)setState((){});});}@override void dispose(){ticker?.cancel();super.dispose();}
 @override Widget build(BuildContext context){final a=widget.store.active;final t=a==null?widget.planned:widget.store.findTraining(a.trainingId);final blocked=a!=null&&widget.planned!=null&&a.trainingId!=widget.planned!.id;return Scaffold(appBar:AppBar(title:const Text('Тренировка')),body:t==null?const Center(child:Text('Выберите тренировку')):SafeArea(child:Padding(padding:const EdgeInsets.all(24),child:Column(children:[const Spacer(),Icon(categoryIcons[t.category]??Icons.circle_outlined,color:colorFor(t.category),size:38),const SizedBox(height:20),Text(t.title,style:const TextStyle(fontSize:24,fontWeight:FontWeight.w500),textAlign:TextAlign.center),const SizedBox(height:28),Container(padding:const EdgeInsets.symmetric(horizontal:8,vertical:30),decoration:BoxDecoration(borderRadius:BorderRadius.circular(36),gradient:RadialGradient(colors:[accent.withValues(alpha:(a?.running==true)?0.22:0.10),const Color(0xFF1A2032),bg],radius:1.1)),child:FittedBox(fit:BoxFit.scaleDown,child:SizedBox(width:310,child:Text(durationText(a?.seconds??0),textAlign:TextAlign.center,style:const TextStyle(fontSize:56,fontWeight:FontWeight.w500,fontFeatures:[FontFeature.tabularFigures()],letterSpacing:0))))),const SizedBox(height:12),Text('План · ${t.plannedMinutes} мин',style:const TextStyle(color:Colors.white60)),const SizedBox(height:48),if(!blocked)FilledButton.icon(onPressed:()async{if(a==null){await widget.store.start(t);await widget.store.togglePause();}else{await widget.store.togglePause();}if(mounted)setState((){});},icon:Icon(a?.running==true?Icons.pause_outlined:Icons.play_arrow_outlined),label:Text(a==null?'Начать':a.running?'Пауза':'Продолжить')),if(!blocked)...[const SizedBox(height:14),OutlinedButton(onPressed:a==null?null:()async{await widget.store.finishTimer();if(!context.mounted)return;Navigator.pop(context);Navigator.push(context,MaterialPageRoute(builder:(_)=>ResultScreen(store:widget.store,training:t)));},child:const Text('Завершить')),TextButton(onPressed:a==null?null:()async{final yes=await showDialog<bool>(context:context,builder:(c)=>AlertDialog(title:const Text('Отменить тренировку?'),content:const Text('Накопленное время не сохранится.'),actions:[TextButton(onPressed:()=>Navigator.pop(c,false),child:const Text('Назад')),TextButton(onPressed:()=>Navigator.pop(c,true),child:const Text('Отменить запуск'))]));if(yes==true){await widget.store.cancelTimer();if(context.mounted)Navigator.pop(context);}},child:const Text('Отменить запуск'))],if(blocked)const Text('Сначала завершите текущую тренировку'),const Spacer()]))));
 }
}
class ResultScreen extends StatefulWidget {const ResultScreen({super.key,required this.store,required this.training});final MoveStore store;final Training training;@override State<ResultScreen> createState()=>_ResultScreenState();}
class _ResultScreenState extends State<ResultScreen>{late TextEditingController mins,note,solved,correct;late int rating;@override void initState(){super.initState();final t=widget.training;mins=TextEditingController(text:'${t.actualSeconds~/60}');note=TextEditingController(text:t.note);solved=TextEditingController(text:t.solved?.toString()??'');correct=TextEditingController(text:t.correct?.toString()??'');rating=t.rating;}@override void dispose(){mins.dispose();note.dispose();solved.dispose();correct.dispose();super.dispose();}
  @override Widget build(BuildContext context){final t=widget.training;return Scaffold(appBar:AppBar(title:const Text('Результат тренировки')),body:ListView(padding:const EdgeInsets.all(20),children:[Text(t.title,style:Theme.of(context).textTheme.headlineSmall),Text('План: ${t.date} · Выполнено: ${t.completedAt?.substring(0,10)??'—'}'),const SizedBox(height:20),TextField(controller:mins,keyboardType:TextInputType.number,decoration:const InputDecoration(labelText:'Фактическое время (минуты)')),const SizedBox(height:20),const Text('Оценка (необязательно)'),Wrap(spacing:4,children:List.generate(5,(i)=>IconButton(onPressed:()=>setState(()=>rating=i+1),icon:Icon(i<rating?Icons.star:Icons.star_border,color:accent)))),const SizedBox(height:12),TextField(controller:note,maxLines:4,decoration:const InputDecoration(labelText:'Заметка (необязательно)')),if(t.category=='Тактика'||t.category=='Расчёт вариантов')... [const SizedBox(height:12),TextField(controller:solved,keyboardType:TextInputType.number,decoration:const InputDecoration(labelText:'Решено задач')),const SizedBox(height:12),TextField(controller:correct,keyboardType:TextInputType.number,decoration:const InputDecoration(labelText:'Правильных ответов'))],const SizedBox(height:24),FilledButton(onPressed:()async{final m=int.tryParse(mins.text);final s=solved.text.trim().isEmpty?null:int.tryParse(solved.text);final c=correct.text.trim().isEmpty?null:int.tryParse(correct.text);if(m==null||m<0||(s!=null&&s<0)||(c!=null&&c<0)||(c!=null&&s==null)||(s!=null&&c!=null&&c>s)){ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Проверьте введённые значения')));return;}t.actualSeconds=m*60;t.rating=rating;t.note=note.text;t.solved=s;t.correct=c;await widget.store.save();if(context.mounted)Navigator.pop(context);},child:const Text('Сохранить'))]));
  }
}
class DiaryScreen extends StatelessWidget {const DiaryScreen({super.key,required this.store});final MoveStore store;
 @override Widget build(BuildContext context){final items=store.trainings.where((x)=>x.done).toList()..sort((a,b)=>b.completedAt!.compareTo(a.completedAt!));return ListView(padding:const EdgeInsets.all(16),children:[const Text('Дневник',style:TextStyle(fontSize:28,fontWeight:FontWeight.w700)),const SizedBox(height:12),if(items.isEmpty)const Padding(padding:EdgeInsets.all(24),child:Text('Завершённые тренировки появятся здесь.')),for(final t in items)Card(child:ListTile(leading:Icon(categoryIcons[t.category],color:colorFor(t.category)),title:Text(t.title),subtitle:Text('${t.actualSeconds~/60} мин · ${t.rating==0?'Без оценки':'${t.rating}/5'}'),onTap:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>ResultScreen(store:store,training:t))),trailing:PopupMenuButton<String>(onSelected:(v)async{if(v!='delete')return;final ok=await showDialog<bool>(context:context,builder:(c)=>AlertDialog(title:const Text('Удалить запись из дневника?'),content:const Text('План останется. Фактическое время и оценка будут удалены.'),actions:[TextButton(onPressed:()=>Navigator.pop(c,false),child:const Text('Отмена')),FilledButton(onPressed:()=>Navigator.pop(c,true),child:const Text('Удалить запись'))]));if(ok==true){t.completedAt=null;t.actualSeconds=0;t.rating=0;t.note='';t.solved=null;t.correct=null;await store.save();}},itemBuilder:(_)=>[const PopupMenuItem(value:'delete',child:Text('Удалить запись'))])))]);}
}
class StatsScreen extends StatefulWidget {const StatsScreen({super.key,required this.store});final MoveStore store;@override State<StatsScreen> createState()=>_StatsScreenState();}
class _StatsScreenState extends State<StatsScreen> {
  int period=0;String? selectedCategory;DateTime? customFrom,customTo;
  DateTime get periodStart {final now=DateTime.now();switch(period){case 0:return now.subtract(Duration(days:now.weekday-1));case 1:return DateTime(now.year,now.month);default:return customFrom??DateTime(now.year,now.month,now.day);}}
  @override Widget build(BuildContext context){
    final start=dayKey(periodStart);
    final end=period==2?dayKey(customTo??DateTime.now()):period==0?dayKey(periodStart.add(const Duration(days:6))):dayKey(DateTime(DateTime.now().year,DateTime.now().month+1,0));
    final done=widget.store.trainings.where((x)=>x.done && x.completedAt!.substring(0,10).compareTo(start)>=0 && x.completedAt!.substring(0,10).compareTo(end)<=0).toList();
    final total=done.fold<int>(0,(s,t)=>s+t.actualSeconds);
    final days=done.map((x)=>x.completedAt!.substring(0,10)).toSet().length;
    final rated=done.where((t)=>t.rating>0).toList();
    final avg=rated.isEmpty?null:rated.fold<int>(0,(s,t)=>s+t.rating)/rated.length;
    final grouped={for(final c in categories)c:done.where((t)=>t.category==c).fold<int>(0,(s,t)=>s+t.actualSeconds)};
    final plan=done.fold<int>(0,(s,t)=>s+t.plannedMinutes);
    return ListView(padding:const EdgeInsets.all(16),children:[
      Text('Статистика',style:Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight:FontWeight.w700)),const SizedBox(height:16),
      SegmentedButton<int>(showSelectedIcon:false,segments:const [ButtonSegment(value:0,label:Text('Неделя')),ButtonSegment(value:2,label:Text('Период'))],selected:{period},onSelectionChanged:(v)async{if(v.first==2){final r=await showDateRangePicker(context:context,firstDate:DateTime(2020),lastDate:DateTime(2100),initialDateRange:DateTimeRange(start:customFrom??DateTime.now().subtract(const Duration(days:30)),end:customTo??DateTime.now()));if(r==null)return;setState((){period=2;customFrom=r.start;customTo=r.end;selectedCategory=null;});}else{setState((){period=0;selectedCategory=null;});}}),const SizedBox(height:18),
      if(done.isEmpty)Card(child:Padding(padding:const EdgeInsets.all(28),child:Column(children:[const Icon(Icons.donut_large_outlined,size:44,color:accent),const SizedBox(height:14),const Text('Пока нет данных за этот период',textAlign:TextAlign.center),const SizedBox(height:8),const Text('Завершите тренировку, чтобы увидеть аналитику.',textAlign:TextAlign.center,style:TextStyle(color:Colors.white70))])))
      else ...[
        Wrap(spacing:10,runSpacing:10,children:[_metric('Фактическое время','${total~/3600} ч ${(total%3600)~/60} м'),_metric('Тренировки','${done.length}'),_metric('Активные дни','$days'),_metric('Средняя оценка',avg==null?'Нет оценок':'${avg.toStringAsFixed(1)} / 5')]),
        const SizedBox(height:20),Text('По категориям',style:Theme.of(context).textTheme.titleLarge),const SizedBox(height:8),
        Card(child:Padding(padding:const EdgeInsets.all(16),child:Column(children:[SizedBox(height:230,child:CustomPaint(painter:CategoryDonutPainter(grouped),child:Center(child:Column(mainAxisSize:MainAxisSize.min,children:[Text('${total~/60}',style:const TextStyle(fontSize:38,fontWeight:FontWeight.w700)),const Text('минут',style:TextStyle(color:Colors.white70))])))),const SizedBox(height:12),for(final c in categories)if(grouped[c]! > 0)InkWell(borderRadius:BorderRadius.circular(10),onTap:()=>setState(()=>selectedCategory=selectedCategory==c?null:c),child:Padding(padding:const EdgeInsets.symmetric(vertical:7),child:Row(children:[Container(width:12,height:12,decoration:BoxDecoration(color:colorFor(c),borderRadius:BorderRadius.circular(4))),const SizedBox(width:10),Expanded(child:Text(c,style:TextStyle(fontWeight:selectedCategory==c?FontWeight.w700:FontWeight.w400))),Text('${grouped[c]!~/60} мин',style:const TextStyle(color:Colors.white70)),const SizedBox(width:10),Text('${(grouped[c]!/total*100).toStringAsFixed(1)}%',style:const TextStyle(color:Colors.white70))])))]))),
        if(selectedCategory!=null)...[const SizedBox(height:14),Text('Тренировки: $selectedCategory',style:Theme.of(context).textTheme.titleMedium),for(final t in done.where((x)=>x.category==selectedCategory))Card(child:ListTile(title:Text(t.title),subtitle:Text('${t.completedAt!.substring(0,10)} · ${t.actualSeconds~/60} мин'),onTap:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>ResultScreen(store:widget.store,training:t)))))],
        const SizedBox(height:18),Card(child:Padding(padding:const EdgeInsets.all(18),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text('План / факт завершённых занятий',style:Theme.of(context).textTheme.titleMedium),const SizedBox(height:8),Text('План: $plan мин · Факт: ${total~/60} мин'),const SizedBox(height:6),const Text('Сравнение только для завершённых занятий; не показатель выполнения всего расписания.',style:TextStyle(color:Colors.white70,fontSize:12))]))),
      ],const SizedBox(height:24)]);
  }
  Widget _metric(String label,String value)=>SizedBox(width:MediaQuery.sizeOf(context).width/2-23,child:Card(child:Padding(padding:const EdgeInsets.all(15),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(value,style:const TextStyle(fontSize:23,fontWeight:FontWeight.w700,color:accent)),const SizedBox(height:5),Text(label,style:const TextStyle(color:Colors.white70,fontSize:12))]))));
}
class CategoryDonutPainter extends CustomPainter {
  CategoryDonutPainter(this.values);final Map<String,int> values;
  @override void paint(Canvas canvas,Size size){final total=values.values.fold<int>(0,(a,b)=>a+b);if(total==0)return;final center=Offset(size.width/2,size.height/2);final radius=(size.shortestSide/2)-15;var angle=-3.141592653589793/2;for(final c in categories){final value=values[c]??0;if(value==0)continue;final sweep=2*3.141592653589793*value/total;final paint=Paint()..color=colorFor(c)..style=PaintingStyle.stroke..strokeWidth=25..strokeCap=StrokeCap.butt;canvas.drawArc(Rect.fromCircle(center:center,radius:radius),angle,sweep,false,paint);angle+=sweep;}}
  @override bool shouldRepaint(covariant CategoryDonutPainter old)=>old.values.toString()!=values.toString();
}
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key,required this.store});
  final MoveStore store;
  @override Widget build(BuildContext context) => ListView(children:[
    const ListTile(title:Text('Настройки',style:TextStyle(fontSize:28,fontWeight:FontWeight.w600))),
    const Divider(),
    SwitchListTile(secondary:const Icon(Icons.notifications_outlined),title:const Text('Напоминания'),
      subtitle:const Text('Перед тренировками с указанным временем'),
      value:store.remindersEnabled,onChanged:(v)=>store.setReminders(v)),
    ListTile(leading:const Icon(Icons.schedule_outlined),title:const Text('Напоминать за'),
      subtitle:Text('${store.reminderLead} мин до начала'),
      enabled:store.remindersEnabled,
      trailing:DropdownButton<int>(value:store.reminderLead,
        items:[0,5,10,15,30,60].map((m)=>DropdownMenuItem(value:m,child:Text('$m мин'))).toList(),
        onChanged:store.remindersEnabled?(m){if(m!=null)store.setReminderLead(m);}:null)),
    ListTile(leading:const Icon(Icons.archive_outlined),title:const Text('Архив моих упражнений'),subtitle:const Text('Восстановление и удаление'),onTap:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>ArchivedExercisesScreen(store:store)))),
    const Divider(),
    const ListTile(leading:Icon(Icons.info_outline),title:Text('MOVE64 0.6.0'),
      subtitle:Text('Данные хранятся локально. Уведомления не требуют интернета.')),
  ]);
}

class ArchivedExercisesScreen extends StatelessWidget {
  const ArchivedExercisesScreen({super.key,required this.store});
  final MoveStore store;
  @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('Архив упражнений')),body:AnimatedBuilder(animation:store,builder:(context,_){final items=store.exercises.where((e)=>e.isCustom&&e.archived).toList();if(items.isEmpty)return const Center(child:Text('В архиве пока нет упражнений',style:TextStyle(color:muted)));return ListView(padding:const EdgeInsets.all(16),children:[for(final e in items)Card(child:ListTile(title:Text(e.title),subtitle:Text(e.category),trailing:PopupMenuButton<String>(onSelected:(action)async{if(action=='restore'){e.archived=false;await store.save();return;}if(action=='delete'){final ok=await showDialog<bool>(context:context,builder:(c)=>AlertDialog(title:const Text('Удалить упражнение навсегда?'),content:const Text('Это действие нельзя отменить. История тренировок сохранится.'),actions:[TextButton(onPressed:()=>Navigator.pop(c,false),child:const Text('Отмена')),FilledButton(onPressed:()=>Navigator.pop(c,true),child:const Text('Удалить'))]));if(ok==true){store.exercises.remove(e);await store.save();}}},itemBuilder:(_)=>[const PopupMenuItem(value:'restore',child:Text('Восстановить')),const PopupMenuItem(value:'delete',child:Text('Удалить навсегда'))])))]);}));
}
