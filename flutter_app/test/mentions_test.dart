import 'package:flutter_test/flutter_test.dart';
import 'package:papocall/models/chat_message.dart';
import 'package:papocall/utils/mentions.dart';

void main() {
  group('Detecção de marcações', () {
    test('encontra os @ citados, em minúsculas e sem repetir', () {
      expect(
        extractMentions('bom dia @Ana e @bruno, @ana viu isso?'),
        {'ana', 'bruno'},
      );
    });

    test('ignora texto sem arroba sem varrer nada', () {
      expect(extractMentions('mensagem comum'), isEmpty);
      expect(extractMentions(''), isEmpty);
    });

    test('não trata e-mail como marcação', () {
      // 'fulano@dominio' marcaria '@dominio' sem a guarda de fronteira.
      expect(extractMentions('me chama em fulano@dominio.com'), isEmpty);
    });

    test('ignora @ curto ou longo demais e caracteres inválidos', () {
      expect(extractMentions('@ab'), isEmpty);
      expect(extractMentions('@${'a' * 21}'), isEmpty);
      expect(extractMentions('@@ana'), isEmpty);
      expect(extractMentions('@joão'), isEmpty);
    });

    test('reconhece marcação colada em pontuação', () {
      expect(extractMentions('(@ana) @bruno, @carla_1!'), {'ana', 'bruno', 'carla_1'});
    });

    test('mentionsUser aceita @ e maiúsculas no alvo', () {
      const texto = 'valeu @Bruno';
      expect(mentionsUser(texto, 'bruno'), isTrue);
      expect(mentionsUser(texto, '@BRUNO'), isTrue);
      expect(mentionsUser(texto, 'ana'), isFalse);
      expect(mentionsUser(texto, ''), isFalse);
    });
  });

  group('Pintura das marcações', () {
    const eu = 'bruno';
    const conhecidos = {'ana', 'carla'};

    test('destaca só quem existe no contexto do leitor', () {
      final segmentos = splitMentions(
        'oi @ana e @fantasma',
        knownHandles: conhecidos,
        selfHandle: eu,
      );

      final marcados = segmentos.where((s) => s.isMention).map((s) => s.handle).toList();
      // '@fantasma' não é ninguém: pintá-lo daria a impressão de que alguém foi
      // avisado quando não foi.
      expect(marcados, ['ana']);
      expect(segmentos.map((s) => s.text).join(), 'oi @ana e @fantasma');
    });

    test('a marcação do próprio leitor vem sinalizada', () {
      final segmentos = splitMentions(
        '@bruno olha isso',
        knownHandles: conhecidos,
        selfHandle: eu,
      );

      final minha = segmentos.firstWhere((s) => s.isMention);
      expect(minha.isSelf, isTrue);
      expect(minha.handle, 'bruno');
    });

    test('preserva o texto original na íntegra', () {
      const original = 'início @ana meio @carla fim';
      final segmentos = splitMentions(
        original,
        knownHandles: conhecidos,
        selfHandle: eu,
      );
      expect(segmentos.map((s) => s.text).join(), original);
    });

    test('texto sem marcação vira um único trecho comum', () {
      final segmentos = splitMentions('só texto', knownHandles: conhecidos, selfHandle: eu);
      expect(segmentos.length, 1);
      expect(segmentos.single.isMention, isFalse);
    });
  });

  group('Autocompletar enquanto digita', () {
    test('reconhece o @ parcial imediatamente antes do cursor', () {
      const texto = 'valeu @an';
      final q = mentionQueryAt(texto, texto.length);

      expect(q, isNotNull);
      expect(q!.term, 'an');
      expect(texto.substring(q.start, q.end), '@an');
    });

    test('dispara com o @ recém-digitado, ainda sem termo', () {
      final q = mentionQueryAt('oi @', 4);
      expect(q?.term, '');
    });

    test('não dispara depois de um espaço ou fora do @', () {
      expect(mentionQueryAt('oi @ana ', 8), isNull);
      expect(mentionQueryAt('sem arroba', 10), isNull);
    });

    test('não dispara dentro de um e-mail', () {
      const texto = 'fulano@dom';
      expect(mentionQueryAt(texto, texto.length), isNull);
    });

    test('usa o cursor, não o fim do texto', () {
      // Cursor no meio: '@an' está antes dele, 'a e @carla' depois.
      const texto = 'oi @ana e @carla';
      final q = mentionQueryAt(texto, 6);
      expect(q?.term, 'an');
    });

    test('desiste de termo maior que um @ válido', () {
      expect(mentionQueryAt('@${'a' * 21}', 22), isNull);
    });
  });

  group('Carimbo de tempo das mensagens', () {
    test('sobrevive ao ciclo de gravação e leitura', () {
      final msg = ChatMessage(
        id: 'm1',
        authorId: 'u1',
        author: 'Ana',
        text: 'oi @bruno',
        timestamp: 'Hoje às 10:00',
        sentAt: 1758240000000,
      );

      final relida = ChatMessage.fromJson(msg.toJson());
      expect(relida.sentAt, 1758240000000);
      expect(relida.text, 'oi @bruno');
    });

    test('mensagem antiga, sem carimbo, chega como 0 e não como agora', () {
      // Datá-la com a hora atual jogaria toda conversa antiga para o fim da
      // tela a cada abertura do app.
      final antiga = ChatMessage.fromJson({
        'id': 'm0',
        'author': 'Ana',
        'text': 'mensagem da versão anterior',
        'timestamp': 'Ontem',
      });
      expect(antiga.sentAt, 0);
    });

    test('mensagem nova recebe carimbo automaticamente', () {
      final agora = DateTime.now().millisecondsSinceEpoch;
      final msg = ChatMessage(
        id: 'm2',
        authorId: 'u1',
        author: 'Ana',
        text: 'oi',
        timestamp: 'Agora',
      );
      expect(msg.sentAt, greaterThanOrEqualTo(agora));
    });
  });
}
