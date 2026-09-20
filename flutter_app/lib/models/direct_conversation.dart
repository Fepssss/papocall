import 'chat_message.dart';
import 'user_model.dart';

/// Uma linha da lista de conversas privadas: com quem, a última mensagem e o
/// que ainda não foi lido.
///
/// É derivado do estado a cada abertura da lista, e não guardado à parte, para
/// que o preview nunca divirja do histórico em disco.
class ConversaDireta {
  const ConversaDireta({
    required this.peer,
    required this.ultima,
    required this.naoLidas,
  });

  final UserModel peer;
  final ChatMessage ultima;
  final int naoLidas;
}
