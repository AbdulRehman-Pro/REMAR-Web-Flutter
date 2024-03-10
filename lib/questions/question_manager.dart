import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class QuestionManager {
  static QuestionManager? _questionManager;
  late SharedPreferences _answerPrefs;
  late int _questionFile;
  late int _previousFile;
  late List<int> _loopCounter;
  late BuildContext _context;
  late List<dynamic>? _cache;

  QuestionManager._(this._context) {
    _questionFile = R.raw.questions;
    SharedPreferences.getInstance().then((prefs) {
      _answerPrefs = prefs;
    });
  }

  static Future<void> init(BuildContext context) async {
    _questionManager = QuestionManager._(context);
    await _questionManager!._init();
  }

  Future<void> _init() async {
    _loopCounter = List.filled(await _getNumberOfLoops(), 1);
  }

  static void changeQuestionFile(int fileID) {
    _questionManager?._questionFile = fileID;
    try {
      _questionManager?._readJSON();
    } catch (e) {}
  }

  static QuestionManager? get() {
    return _questionManager;
  }

  Future<List<Map<String, dynamic>>> exportAnswers() async {
    List<Map<String, dynamic>> lst = [];
    String? baseAnswersString =
    _answerPrefs.getString(_containerToAnswerKey(null));
    Map<String, dynamic> baseAnswers = json.decode(baseAnswersString ?? '{}');
    lst.add(baseAnswers);
    for (Map<String, dynamic> loop in _getLoops(await _readJSON())) {
      List<Map<String, dynamic>> newLst = [];
      int loopLength = await _getQuestionCountInContainer(loop['questions']);
      int loopCount = _loopCounter[loop['loop']];
      String answersKey = _containerToAnswerKey(loop);
      Map<String, dynamic> answers =
      json.decode(_answerPrefs.getString(answersKey) ?? '{}');
      for (Map<String, dynamic> obj in lst) {
        for (int i = 0; i < loopCount; i++) {
          Map<String, dynamic> newObj =
          _duplicateJSONObject(obj, 0, loopLength);
          for (int j = 0; j < loopLength; j++) {
            newObj['$j'] = answers['${i * loopLength + j}'];
          }
          newLst.add(newObj);
        }
        await _answerPrefs.remove(answersKey);
      }
      lst = newLst;
    }
    await _answerPrefs.remove(_containerToAnswerKey(null));
    await _init(); // Reinitialize to reset question loops
    return lst;
  }

  Future<Map<String, dynamic>> _readJSON() async {
    if (_cache == null || _previousFile != _questionFile) {
      ByteData data = await rootBundle.load('assets/questions.json');
      String jsonString = utf8.decode(data.buffer.asUint8List());
      _cache = json.decode(jsonString);
      _previousFile = _questionFile;
    }
    return Map<String, dynamic>.from(_cache! as Map);
  }

  Future<Map<String, dynamic>> getJsonQuestion(int id) async {
    Map<String, dynamic>? container =
    await _getContainer(id, await _readJSON(), null);
    return container!['fourth'];
  }

  Future<int> _getQuestionCount(bool withNumberOnly, Map<String, dynamic> obj) async {
    int count = 0, loopId = 0;
    List<dynamic> array = obj['questions'];
    for (int i = 0; i < array.length; i++) {
      Map<String, dynamic> object = array[i];
      if (object.containsKey('loop')) {
        int subCount =
        await _getQuestionCount(withNumberOnly, object['questions']);
        count += subCount * _loopCounter[loopId];
      } else {
        if (!withNumberOnly || object.containsKey('questionNumber')) {
          count++;
        }
        if (object.containsKey('jumpOn')) {
          List<String> split = object['jumpOn'].split('->');
          try {
            List<String> split2 = split[0].split(':');
            Map<String, dynamic> answer = await getAnswer(int.parse(split2[0]));
            if (answer[split2[1]] == '1') {
              i += int.parse(split[1]);
              i += 1; // TODO check logic error
            }
          } catch (e) {}
        }
      }
    }
    return count;
  }

  Future<int> getQuestionCount() async {
    return await _getQuestionCount(true, await _readJSON());
  }

  Future<int> getRealQuestionCount() async {
    return await _getQuestionCount(false, await _readJSON());
  }

  Future<Map<String, dynamic>> getCurrentAnswers(String container) async {
    String? answers = _answerPrefs.getString(container);
    return json.decode(answers ?? '{}');
  }

  Future<Map<String, dynamic>> getAnswer(int id) async {
    Map<String, dynamic>? container =
    await _getContainer(id, await _readJSON(), null);
    Map<String, dynamic> answers =
    await getCurrentAnswers(_containerToAnswerKey(container!['first']));
    return answers['${container['second']}'];
  }

  Future<void> saveAnswer(int id, List<dynamic>? answer) async {
    if (answer == null) {
      print('Q$id No answer given.');
    }
    Map<String, dynamic>? container =
    await _getContainer(id, await _readJSON(), null);
    Map<String, dynamic> answers =
    await getCurrentAnswers(_containerToAnswerKey(container!['first']));
    answers['${container['second']}'] = answer;
    int questionCount = await _getQuestionCountInContainer(container['third']);
    if ((container['second'] + 1) % questionCount == 0) {
      if (container['first'] != null &&
          container['first']['loop'] != null &&
          container['first']['stopOn'] != null) {
        List<String> saveTo = container['first']['stopOn'].split(':');
        int loopCount = (container['second'] + 1) ~/ questionCount;
        int loopId = container['first']['loop'];
        if (answers[saveTo[0]] == saveTo[1]) {
          _loopCounter[loopId] = loopCount;
          print('Ending loop $loopId');
        } else {
          print('Looping $loopId');
          int count = _loopCounter[loopId];
          if (count <= loopCount) {
            _loopCounter[loopId] = loopCount + 1;
            print('Extending loop to ${loopCount + 1}');
          } else {
            print('Not extending loop count. $count > $loopCount');
          }
        }
      }
    }
    String newAnswers = json.encode(answers);
    await _answerPrefs.setString(
        _containerToAnswerKey(container['first']), newAnswers);
    print('New answers: ${_containerToAnswerKey(container['first'])} : $newAnswers');
  }

  Future<int> _getNumberOfLoops() async {
    int count = 0;
    Map<String, dynamic> obj = await _readJSON();
    List<dynamic> array = obj.values.toList();
    for (int i = 0; i < array.length; i++) {
      Map<String, dynamic> subObj = array[i];
      if (subObj.containsKey('loop')) {
        count++;
      }
    }
    return count;
  }

  Future<Map<String, dynamic>?> _getContainer(int id, Map<String, dynamic> obj, Map<String, dynamic>? parent) async {
    int questionId = 0;
    List<dynamic> array = obj['questions'];
    for (int i = 0; i < array.length; i++) {
      Map<String, dynamic> object = array[i];
      if (object.containsKey('loop')) {
        List<dynamic> subArray = object['questions'];
        for (int j = 1; j <= _loopCounter[object['loop']]; j++) {
          Map<String, dynamic>? found =
          await _getContainer(id - (i * j), subArray, object);
          id -= (subArray.length); // Remove subquestions from total
          if (found != null) {
            int questionCount = await _getQuestionCountInContainer(subArray);
            return {
              'first': found['first'],
              'second': found['second'] + ((j - 1) * questionCount),
              'third': subArray
            };
          }
        }
      } else {
        if (questionId == id) {
          if (parent != null) {
            return {'first': parent, 'second': questionId, 'third': array, 'fourth': object};
          } else {
            return {'first': parent, 'second': questionId, 'third': array, 'fourth': object};
          }
        } else {
          if (object.containsKey('jumpOn')) {
            List<String> split = object['jumpOn'].split('->');
            List<String> split2 = split[0].split(':');
            Map<String, dynamic> answer = await getAnswer(int.parse(split2[0]));
            if (answer[split2[1]] == '1') {
              id += int.parse(split[1]);
              continue;
            }
          }
          questionId++;
        }
      }
    }
    return null;
  }

  Future<int> _getQuestionCountInContainer(List<dynamic> array) async {
    int count = 0;
    for (int i = 0; i < array.length; i++) {
      Map<String, dynamic> obj = array[i];
      if (!obj.containsKey('loop')) {
        count++;
      }
    }
    return count;
  }

  String _containerToAnswerKey(Map<String, dynamic>? container) {
    if (container != null) {
      return 'answers_key_${container['loop']}';
    } else {
      return 'answers_key_base';
    }
  }

  Map<String, dynamic> _duplicateJSONObject(Map<String, dynamic> old, int position, int offset) {
    Map<String, dynamic> newObj = {};
    old.forEach((key, value) {
      int intKey = int.parse(key);
      if (intKey >= position) {
        key = (intKey + offset).toString();
      }
      newObj[key] = value;
    });
    return newObj;
  }

  List<dynamic> _getLoops(Map<String, dynamic> obj) {
    List<dynamic> lst = [];
    List<dynamic> array = obj.values.toList();
    for (int i = 0; i < array.length; i++) {
      Map<String, dynamic> subObj = array[i];
      if (subObj.containsKey('loop')) {
        lst.add(subObj);
        List<dynamic> subarray = _getLoops(subObj);
        lst.addAll(subarray);
      }
    }
    return lst;
  }
}
