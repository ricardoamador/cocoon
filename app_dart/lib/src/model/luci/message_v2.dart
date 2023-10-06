import 'package:cocoon_service/cocoon_service.dart';
import 'package:cocoon_service/src/model/common/json_converters.dart';
import 'package:json_annotation/json_annotation.dart';

part 'message_v2.g.dart';

// Rename this to PushMessage as it is basically that class.
@JsonSerializable(includeIfNull: false)
class MessageV2 extends JsonBody{
  const MessageV2({this.attributes, this.data, this.messageId, this.publishTime});
  
  /// PubSub attributes on the message.
  final Map<String, String>? attributes;

  @Base64Converter()
  final String? data;
  
  final String? messageId;
  
  final String? publishTime;
  
  static MessageV2 fromJson(Map<String, dynamic> json) => _$MessageV2FromJson(json);

  @override
  Map<String, dynamic> toJson() => _$MessageV2ToJson(this);
}