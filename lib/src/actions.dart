import 'base.dart';
import 'dispatcher.dart';
import 'structure.dart';

mixin BaseActions on Sender, Dispatcher {
  Future<Response?> login(String name, String pass) {
    return sendAction('Login', args: {'Username': name, 'Secret': pass});
  }

  Future<Response?> logoff() {
    return sendAction('Logoff');
  }

  void call(String from, String to, Function onStart, Function(DateTime startTime, Duration duration) onEnd, [int priority = 1, int timeout = 30000]) {
    String? linkedId;
    sendAction('Originate', args: {'Context': 'DLPN_DialPlan$from', 'Channel': 'PJSIP/$from', 'CallerID': from, 'Exten': to, 'Priority': priority.toString(), 'Timeout': timeout.toString()}).then((response) {
      if(response != null) {
        if(response.succeed) {
          readEvent('Newchannel').then((event) {
            linkedId = event.baseMsg.headers['Linkedid'];
            onStart();
          });
          readEvent('Cdr').then((event) {
            var headers = event.baseMsg.headers;
            print(headers.toString());
            if(linkedId != null) {
              if(headers['LinkedID'] == linkedId){
                DateTime startTime = DateTime.parse(headers['StartTime']!);
                DateTime answerTime = DateTime.parse(headers['AnswerTime']!);
                DateTime endTime = DateTime.parse(headers['EndTime']!);
                onEnd(startTime, endTime.difference(answerTime));
              }
            }
          });
        }
      }
    });
  }

  void incomingCallHandler(Function(String from, String to) onStart, Function(DateTime startTime, Duration duration) onEnd) async {
    String? linkedId;
    registerEvent('DialBegin').listen((event) {
      print(event.baseMsg.headers.toString());
      linkedId = event.baseMsg.headers['Linkedid'];
      onStart(event.baseMsg.headers['CallerIDNum']??"", event.baseMsg.headers['DestCallerIDNum']??"");
    });
    registerEvent('Cdr').listen((event) {
      var headers = event.baseMsg.headers;
      print(headers.toString());
      if(linkedId != null) {
        if(headers['LinkedID'] == linkedId){
          DateTime startTime = DateTime.parse(headers['StartTime']!);
          DateTime answerTime = DateTime.parse(headers['AnswerTime']!);
          DateTime endTime = DateTime.parse(headers['EndTime']!);
          onEnd(startTime, endTime.difference(answerTime));
        }
      }
    });
  }
}
// Action: Originate
// ActionID: kawjefoin23kj
// Context: DLPN_DialPlan1001
// Channel: PJSIP/1001
// Exten: 07704302300
// Priority: 1
// Timeout: 30000
// CallerID: 1001