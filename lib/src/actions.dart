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

  //TODO: implement linkedId
  void call(String from, String to, Function onStart,
      Function(DateTime startTime, Duration duration) onEnd,
      [int priority = 1, int timeout = 30000]) {
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
          callHandler((from, to, type, linkedId) => onStart(from, to),
              (startTime, duration, type, linkedId) => onEnd(startTime, duration));
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

  void callHandler(Function(String from, String to, int type, String linkedId) onStart,
      Function(DateTime startTime, Duration duration, int type, String linkedId) onEnd) async {
    List<String> linkedIds = [];
    CallType callType = CallType.ringing;
    registerEvent('DialBegin').listen((event) {
      final headers = event.baseMsg.headers;
      print(headers.toString());
      String? linkedId = headers['Linkedid'];
      if (linkedId != null && !linkedIds.contains(linkedId)) {
        linkedIds.add(linkedId);
        final sourceChannel = headers['Channel'] ?? "";
        final destChannel = headers['DestChannel'] ?? "";
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
            callType.index,
            linkedId);
      }
    });
    registerEvent('Cdr').listen((event) {
      final headers = event.baseMsg.headers;
      final linkedId = headers['LinkedID'];
      callType = headers['UserField'] == 'Inbound' ? CallType.ringing : headers['UserField'] == 'Outbound' ? CallType.outgoing : CallType.internal;
      print(headers.toString());
      if (linkedIds.contains(linkedId)) {
        final DateTime startTime = DateTime.parse(headers['StartTime']!);
        final DateTime? answerTime = DateTime.tryParse(headers['AnswerTime']!);
        final DateTime endTime = DateTime.parse(headers['EndTime']!);
        final destContext = headers['DestinationContext'];
        if (destContext != null &&
            destContext.startsWith('ringgroup')) {
          if (headers['Destination'] == destContext.split('_')[1] &&
                  answerTime == null ||
              headers['Destination'] != destContext.split('_')[1] &&
                  answerTime != null) {
            linkedIds.remove(linkedId);
          }
        } else {
          linkedIds.remove(linkedId);
        }
        if(!linkedIds.contains(linkedId))
          onEnd(
              startTime,
              callType == CallType.ringing ? endTime.difference(answerTime ?? startTime) : endTime.difference(answerTime ?? endTime),
              callType == CallType.ringing
                  ? answerTime == null
                  ? CallType.missed.index
                  : CallType.incoming.index
                  : callType.index,
              linkedId!);
      }
    });
  }
}
