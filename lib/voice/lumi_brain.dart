import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;

/// What the friend says back, and the one thing it does to show you.
class LumiAnswer {
  const LumiAnswer(this.say, {this.action = LumiAction.none, this.target});

  /// A short, spoken-style reply.
  final String say;
  final LumiAction action;

  /// What the action is about: a card, a ride, a screen, a weather, a moment.
  final String? target;

  @override
  String toString() => 'LumiAnswer($say, ${action.name}, $target)';
}

/// Everything the friend can do to answer.
enum LumiAction {
  /// Just talk.
  none,

  /// Scroll to a card and point it out: tonight, reward, weather, booth,
  /// games, map, waits, dining, shows.
  showCard,

  /// Light up one row: a ride, a place to eat, or a show, by name.
  highlight,

  /// Open the park map and walk to a ride, by name.
  walkTo,

  /// Open a screen: show, catch, lift, booth, wardrobe, room.
  open,

  /// Set the weather: rain, heat, clear.
  weather,

  /// Play a moment: trick, sneeze, pulse, pratfall, lights_out, jenga,
  /// peel, eat.
  moment,
}

/// What the friend knows about the park right now.
class ParkFacts {
  const ParkFacts({
    required this.friend,
    required this.waits,
    required this.dining,
    required this.shows,
    required this.weather,
    required this.keys,
    required this.dayPart,
  });

  final String friend;
  final List<(String, int)> waits;
  final List<(String, String)> dining;
  final List<(String, String)> shows;
  final String weather;
  final int keys;
  final String dayPart;

  String describe() => [
        'Ride waits: ${waits.map((w) => '${w.$1} ${w.$2} min').join(', ')}.',
        'Dining: ${dining.map((d) => '${d.$1} (${d.$2})').join(', ')}.',
        'Shows: ${shows.map((s) => '${s.$1} at ${s.$2}').join(', ')}. The fireworks are over the lagoon.',
        'Weather: $weather.',
        'Lagoon Keys found: $keys of 5 (a reward card lets the friend fetch one).',
        'It is $dayPart.',
      ].join('\n');
}

/// Answers a question about the park.
abstract class LumiBrain {
  Future<LumiAnswer> answer(String question, ParkFacts facts);

  /// Gemini when a key is configured, the built-in matcher otherwise (and
  /// whenever Gemini fails or is slow, so a demo never stalls).
  static LumiBrain create() {
    const fromDefine = String.fromEnvironment('GEMINI_API_KEY');
    // The web has no environment, so there the key only comes from --dart-define.
    final key = fromDefine.isNotEmpty || kIsWeb ? fromDefine : (Platform.environment['GEMINI_API_KEY'] ?? '');
    const model = String.fromEnvironment('GEMINI_MODEL', defaultValue: 'gemini-2.5-flash');
    final local = LocalBrain();
    if (key.isEmpty) return local;
    return _Fallback(GeminiBrain(key, model: model), local);
  }
}

class _Fallback implements LumiBrain {
  _Fallback(this.primary, this.backup);
  final LumiBrain primary;
  final LumiBrain backup;

  @override
  Future<LumiAnswer> answer(String question, ParkFacts facts) async {
    try {
      return await primary.answer(question, facts).timeout(const Duration(seconds: 6));
    } catch (_) {
      return backup.answer(question, facts);
    }
  }
}

/// Gemini, asked for a structured reply: what to say and one action.
class GeminiBrain implements LumiBrain {
  GeminiBrain(this._key, {required this.model});

  final String _key;
  final String model;
  final _client = http.Client();

  static const _actions = ['none', 'show_card', 'highlight', 'walk_to', 'open', 'weather', 'moment'];

  String _system(ParkFacts f) => '''
You are ${f.friend}, a tiny glowing lantern spirit who lives at the top of a theme park app and helps guests. You are warm, playful, and brief.

Answer in at most 20 words, spoken style, no emoji, no markdown. Only state facts from the park data below; if you do not know, say so cheerfully and suggest something you can show.

Pick exactly one action that shows the answer on screen:
- show_card: point at a card. target is one of tonight, reward, weather, booth, games, map, waits, dining, shows.
- highlight: light up one row. target is a ride, a place to eat, or a show, named exactly as below.
- walk_to: open the park map and walk there. target is a ride named exactly as below.
- open: open a screen. target is one of show (the fireworks), catch (the Star Catch game), lift (the Sky Lift game), booth (photo booth), wardrobe (hats and friends), room (your room).
- weather: change the weather. target is rain, heat, or clear.
- moment: do something fun. target is one of trick, sneeze, pulse, pratfall, lights_out, jenga, peel, eat.
- none: just talk.

Park data:
${f.describe()}
''';

  @override
  Future<LumiAnswer> answer(String question, ParkFacts facts) async {
    Map<String, Object?> body({required bool fast}) => {
          'systemInstruction': {
            'parts': [
              {'text': _system(facts)},
            ],
          },
          'contents': [
            {
              'role': 'user',
              'parts': [
                {'text': question},
              ],
            },
          ],
          'generationConfig': {
            'temperature': 0.7,
            'maxOutputTokens': 256,
            'responseMimeType': 'application/json',
            'responseSchema': {
              'type': 'OBJECT',
              'properties': {
                'say': {'type': 'STRING'},
                'action': {'type': 'STRING', 'enum': _actions},
                'target': {'type': 'STRING'},
              },
              'required': ['say', 'action'],
            },
            // Answers should come back fast; no long deliberation.
            if (fast) 'thinkingConfig': {'thinkingBudget': 0},
          },
        };
    final uri = Uri.parse('https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent');
    Future<http.Response> send(bool fast) => _client.post(
          uri,
          headers: {'content-type': 'application/json', 'x-goog-api-key': _key},
          body: jsonEncode(body(fast: fast)),
        );
    var res = await send(true);
    // Models without a thinking budget reject it; ask again without.
    if (res.statusCode == 400) res = await send(false);
    if (res.statusCode != 200) throw HttpException('Gemini ${res.statusCode}');
    final json = jsonDecode(res.body) as Map<String, Object?>;
    final parts = (((json['candidates'] as List).first as Map)['content'] as Map)['parts'] as List;
    final text = parts.map((p) => (p as Map)['text'] ?? '').join();
    final reply = jsonDecode(text) as Map<String, Object?>;
    final action = switch (reply['action']) {
      'show_card' => LumiAction.showCard,
      'highlight' => LumiAction.highlight,
      'walk_to' => LumiAction.walkTo,
      'open' => LumiAction.open,
      'weather' => LumiAction.weather,
      'moment' => LumiAction.moment,
      _ => LumiAction.none,
    };
    return LumiAnswer((reply['say'] as String? ?? '').trim(), action: action, target: (reply['target'] as String?)?.trim());
  }
}

/// A small built-in matcher for the questions people actually ask, so the
/// friend answers with no key and no network.
class LocalBrain implements LumiBrain {
  @override
  Future<LumiAnswer> answer(String question, ParkFacts f) async {
    final q = question.toLowerCase();
    bool has(List<String> words) => words.any(q.contains);
    String? ride() => f.waits.map((w) => w.$1).where((n) => q.contains(n.toLowerCase()) || q.contains(n.split(' ').first.toLowerCase())).firstOrNull;

    final named = ride();
    if (named != null && has(['take me', 'go to', 'get to', 'where is', 'where\'s', 'walk', 'show me the way', 'how do i'])) {
      return LumiAnswer('Follow me! Hopping over to $named.', action: LumiAction.walkTo, target: named);
    }
    if (has(['shortest', 'quickest', 'least', 'no line', 'short line', 'fastest', 'best ride', 'what should i ride', 'what ride'])) {
      final best = (List.of(f.waits)..sort((a, b) => a.$2.compareTo(b.$2))).first;
      return LumiAnswer('${best.$1} is only ${best.$2} minutes right now. Quick, before it fills up!', action: LumiAction.highlight, target: best.$1);
    }
    if (has(['longest', 'busiest', 'most popular'])) {
      final worst = (List.of(f.waits)..sort((a, b) => b.$2.compareTo(a.$2))).first;
      return LumiAnswer('${worst.$1} has the longest line, ${worst.$2} minutes. Maybe later?', action: LumiAction.highlight, target: worst.$1);
    }
    if (named != null) {
      final w = f.waits.firstWhere((w) => w.$1 == named);
      return LumiAnswer('$named is ${w.$2} minutes right now.', action: LumiAction.highlight, target: named);
    }
    if (has(['firework', 'tonight', 'show'])) {
      return const LumiAnswer('Fireworks over the lagoon at 9:15. I saved us a spot!', action: LumiAction.showCard, target: 'tonight');
    }
    if (has(['eat', 'food', 'hungry', 'dinner', 'lunch', 'restaurant', 'snack', 'drink', 'café', 'cafe'])) {
      return const LumiAnswer('Lantern Café has a table for two, and Starlight Treats is open till ten.', action: LumiAction.showCard, target: 'dining');
    }
    if (has(['make it rain', 'let it rain', 'can it rain'])) {
      return const LumiAnswer('Umbrella time!', action: LumiAction.weather, target: 'rain');
    }
    if (has(['make it sunny', 'make it hot', 'heat wave'])) {
      return const LumiAnswer('Sunglasses on!', action: LumiAction.weather, target: 'heat');
    }
    if (has(['weather', 'rain', 'cold', 'hot', 'umbrella', 'temperature'])) {
      return LumiAnswer('${f.weather[0].toUpperCase()}${f.weather.substring(1)}. Perfect for fireworks!', action: LumiAction.showCard, target: 'weather');
    }
    if (has(['wait', 'line', 'how long'])) {
      return const LumiAnswer('Here are all the waits. I keep them fresh!', action: LumiAction.showCard, target: 'waits');
    }
    if (has(['map', 'where am i', 'lost', 'directions'])) {
      return const LumiAnswer('Let me show you the whole park!', action: LumiAction.showCard, target: 'map');
    }
    if (has(['key', 'reward', 'collect', 'prize'])) {
      return LumiAnswer('You have ${f.keys} of 5 Lagoon Keys. There is one nearby!', action: LumiAction.showCard, target: 'reward');
    }
    if (has(['photo', 'picture', 'selfie', 'camera'])) {
      return const LumiAnswer('Say cheese! Let\'s take one together.', action: LumiAction.open, target: 'booth');
    }
    if (has(['game', 'play', 'bored'])) {
      return const LumiAnswer('Let\'s catch some falling stars!', action: LumiAction.open, target: 'catch');
    }
    if (has(['hat', 'outfit', 'dress', 'wear', 'wardrobe'])) {
      return const LumiAnswer('Ooh, dress-up time! Pick me something cute.', action: LumiAction.open, target: 'wardrobe');
    }
    if (has(['dark', 'lights', 'sleep', 'night night'])) {
      return const LumiAnswer('Lights out! I\'ll be your night light.', action: LumiAction.moment, target: 'lights_out');
    }
    if (has(['3d', 'magic', 'something cool', 'surprise', 'wow'])) {
      return const LumiAnswer('Hold on to something!', action: LumiAction.moment, target: 'peel');
    }
    if (has(['trick', 'dance', 'fun'])) {
      return const LumiAnswer('Watch this!', action: LumiAction.moment, target: 'trick');
    }
    if (has(['hello', 'hi ', 'hey', 'who are you', 'your name', 'what are you'])) {
      return LumiAnswer('Hi! I\'m ${f.friend}, your park buddy. Ask me about rides, food, or the fireworks!');
    }
    return const LumiAnswer('Hmm, I\'m not sure! Ask me about rides, food, or the fireworks.');
  }
}
