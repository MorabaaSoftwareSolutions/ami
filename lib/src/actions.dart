import 'base.dart';
import 'dispatcher.dart';
import 'structure.dart';

enum CallType { ringing, missed, incoming, outgoing, internal, unknown }

mixin BaseActions on Sender, Dispatcher {
  Future<Response?> login(String name, String pass) {
    return sendAction('Login', args: {'Username': name, 'Secret': pass});
  }

  Future<Response?> logoff() {
    return sendAction('Logoff');
  }

  void call(String from, String to, Function onStart,
      Function(DateTime startTime, Duration duration) onEnd,
      [int priority = 1, int timeout = 30000]) {
    String? linkedId;
    sendAction('Originate', args: {
      'Context': 'DLPN_DialPlan$from',
      'Channel': 'PJSIP/$from',
      'CallerID': from,
      'Exten': to,
      'Priority': priority.toString(),
      'Timeout': timeout.toString()
    }).then((response) {
      if (response != null) {
        if (response.succeed) {
          callHandler((from, to, type) => onStart(from, to),
              (startTime, duration, type) => onEnd(startTime, duration));
          // readEvent('Newchannel').then((event) {
          //   linkedId = event.baseMsg.headers['Linkedid'];
          //   onStart();
          // });
          // readEvent('Cdr').then((event) {
          //   var headers = event.baseMsg.headers;
          //   print(headers.toString());
          //   if (linkedId != null) {
          //     if (headers['LinkedID'] == linkedId) {
          //       DateTime startTime = DateTime.parse(headers['StartTime']!);
          //       DateTime answerTime = DateTime.parse(headers['AnswerTime']!);
          //       DateTime endTime = DateTime.parse(headers['EndTime']!);
          //       onEnd(startTime, endTime.difference(answerTime));
          //     }
          //   }
          // });
        }
      }
    });
  }

  void callHandler(Function(String from, String to, int type) onStart,
      Function(DateTime startTime, Duration duration, int type) onEnd) async {
    List<String> linkedIds = [];
    late CallType callType;
    registerEvent('DialBegin').listen((event) {
      var headers = event.baseMsg.headers;
      print(headers.toString());
      String? linkedId = headers['Linkedid'];
      if(linkedId != null && !linkedIds.contains(linkedId)) {
        linkedIds.add(linkedId);
        var sourceChannel = headers['Channel'] ?? "";
        var destChannel = headers['DestChannel'] ?? "";
        if (sourceChannel.startsWith('PJSIP/trunk') &&
            destChannel.startsWith(RegExp(r'PJSIP/[0-9]'))) {
          callType = CallType.ringing;
        } else if (sourceChannel.startsWith(RegExp(r'PJSIP/[0-9]')) &&
            destChannel.startsWith('PJSIP/trunk')) {
          callType = CallType.outgoing;
        } else if (sourceChannel.startsWith(RegExp(r'PJSIP/[0-9]')) &&
            destChannel.startsWith(RegExp(r'PJSIP/[0-9]'))) {
          callType = CallType.internal;
        }
        onStart(
            headers['CallerIDNum'] ?? headers['CallerIDName'] ?? "",
            headers['DestCallerIDNum'] ?? headers['DestCallerIDName'] ?? "",
            callType.index);
      }
    });
    registerEvent('Cdr').listen((event) {
      var headers = event.baseMsg.headers;
      print(headers.toString());
      if (linkedIds.contains(headers['LinkedID'])) {
          DateTime startTime = DateTime.parse(headers['StartTime']!);
          DateTime? answerTime = DateTime.tryParse(headers['AnswerTime']!);
          DateTime endTime = DateTime.parse(headers['EndTime']!);
          onEnd(
              startTime,
              endTime.difference(answerTime ?? startTime),
              callType == CallType.ringing
                  ? answerTime == null
                      ? CallType.missed.index
                      : CallType.incoming.index
                  : callType.index);
          linkedIds.remove(headers['LinkedID']);
      }
    });
  }
}
