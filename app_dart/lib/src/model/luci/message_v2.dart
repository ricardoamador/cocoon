import 'package:cocoon_service/cocoon_service.dart';
import 'package:cocoon_service/src/model/common/json_converters.dart';
import 'package:gcloud/pubsub.dart';
import 'package:json_annotation/json_annotation.dart';

part 'message_v2.g.dart';

@JsonSerializable(includeIfNull: false)
class MessageV2 extends JsonBody{
  const MessageV2({this.message, this.messageId, this.publishTime});
  
  @Base64Converter()
  final String? data;

  final Message? message; 
  
  final String? messageId;
  
  final String? publishTime;
  
}