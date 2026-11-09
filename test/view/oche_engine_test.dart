import 'package:oche/src/view/oche_engine.dart';
import 'package:oche/src/view/view_engine.dart';
import 'package:test/test.dart';

Future<String> render(
  Map<String, String> templates,
  String name, [
  Map<String, Object?> data = const <String, Object?>{},
]) {
  return const OcheEngine().render(name, data, (String n) async {
    final source = templates[n];
    if (source == null) throw TemplateError('missing template $n');
    return source;
  });
}

class _User {
  Map<String, Object?> toJson() => {'name': 'Ana'};
}

void main() {
  group('output', () {
    test('escapes {{ }} and keeps {!! !!} raw', () async {
      final html = await render(
        {'t': 'Hi {{ name }} / {!! name !!}'},
        't',
        {'name': '<b>'},
      );

      expect(html, 'Hi &lt;b&gt; / <b>');
    });

    test('reads nested maps, list indexes and length', () async {
      final html = await render(
        {'t': '{{ user.name }} {{ items.1 }} {{ items.length }}'},
        't',
        {
          'user': {'name': 'Ana'},
          'items': ['a', 'b'],
        },
      );

      expect(html, 'Ana b 2');
    });

    test('missing values print as empty', () async {
      final html = await render(
        {'t': '[{{ missing }}][{{ user.nope.deep }}]'},
        't',
        {'user': <String, Object?>{}},
      );

      expect(html, '[][]');
    });

    test('reads objects through toJson()', () async {
      final html = await render({'t': '{{ user.name }}'}, 't', {'user': _User()});

      expect(html, 'Ana');
    });

    test('removes comments, supports @@ and leaves e-mails alone', () async {
      final html = await render(
        {'t': 'a{{-- hidden --}}b @@if c user@example.com'},
        't',
      );

      expect(html, 'ab @if c user@example.com');
    });
  });

  group('conditions', () {
    const template = '@if(n > 5)big@elseif(n > 2)mid@else[small]@endif';

    test('chooses the right branch', () async {
      expect(await render({'t': template}, 't', {'n': 10}), 'big');
      expect(await render({'t': template}, 't', {'n': 3}), 'mid');
      expect(await render({'t': template}, 't', {'n': 1}), '[small]');
    });

    test('supports && || ! and comparisons', () async {
      const t = '@if(age >= 18 && !banned)ok@endif';

      expect(await render({'t': t}, 't', {'age': 20, 'banned': false}), 'ok');
      expect(await render({'t': t}, 't', {'age': 20, 'banned': true}), '');
      expect(await render({'t': t}, 't', {'age': 10, 'banned': false}), '');
    });

    test('compares strings and mixes == with <', () async {
      expect(
        await render({'t': "@if(role == 'admin')A@endif"}, 't', {'role': 'admin'}),
        'A',
      );
      expect(await render({'t': '@if(1 < 2 == true)yes@endif'}, 't'), 'yes');
    });

    test('treats empty lists and null as false', () async {
      const t = '@if(items)full@else[empty]@endif';

      expect(await render({'t': t}, 't', {'items': <int>[]}), '[empty]');
      expect(await render({'t': t}, 't'), '[empty]');
      expect(await render({'t': t}, 't', {'items': [1]}), 'full');
    });
  });

  group('loops', () {
    test('@foreach with the loop variable', () async {
      final html = await render(
        {'t': '@foreach(items as item){{ loop.iteration }}={{ item }};@endforeach'},
        't',
        {'items': ['a', 'b']},
      );

      expect(html, '1=a;2=b;');
    });

    test('@foreach over a map with key => value', () async {
      final html = await render(
        {'t': '@foreach(m as k => v){{ k }}:{{ v }},@endforeach'},
        't',
        {'m': {'x': 1, 'y': 2}},
      );

      expect(html, 'x:1,y:2,');
    });

    test('loop.first and loop.last', () async {
      final html = await render(
        {
          't': '@foreach(items as i)@if(loop.first)[@endif{{ i }}'
              '@if(loop.last)]@endif@endforeach',
        },
        't',
        {'items': [1, 2, 3]},
      );

      expect(html, '[123]');
    });
  });

  group('includes and layouts', () {
    test('@include shares the variables', () async {
      final html = await render(
        {
          'main': "A @include('part') B",
          'part': 'Hi {{ name }}',
        },
        'main',
        {'name': 'Ana'},
      );

      expect(html, 'A Hi Ana B');
    });

    test('@extends fills the sections of a layout', () async {
      final templates = {
        'layout': "<t>@yield('title', 'Default')</t><b>@yield('content')</b>",
        'child': "@extends('layout')@section('content')Hello {{ name }}@endsection",
      };

      expect(
        await render(templates, 'child', {'name': 'Ana'}),
        '<t>Default</t><b>Hello Ana</b>',
      );
    });

    test('a section replaces the @yield default', () async {
      final templates = {
        'layout': "<t>@yield('title', 'Default')</t>",
        'child': "@extends('layout')@section('title')Mine@endsection",
      };

      expect(await render(templates, 'child'), '<t>Mine</t>');
    });

    test('layouts can extend other layouts, the leaf wins', () async {
      final templates = {
        'base': "[@yield('a')]",
        'mid': "@extends('base')@section('a')mid@endsection",
        'leaf': "@extends('mid')@section('a')leaf@endsection",
      };

      expect(await render(templates, 'leaf'), '[leaf]');
    });

    test('include loops are stopped', () async {
      final templates = {'a': "@include('a')"};

      expect(render(templates, 'a'), throwsA(isA<TemplateError>()));
    });
  });

  group('errors', () {
    test('an @if without @endif', () {
      expect(
        render({'t': '@if(x)unclosed'}, 't'),
        throwsA(isA<TemplateError>()),
      );
    });

    test('a stray @endif', () {
      expect(render({'t': 'a @endif'}, 't'), throwsA(isA<TemplateError>()));
    });

    test('an invalid expression reports the line', () {
      expect(
        render({'t': 'line 1\n{{ 1 + }}'}, 't'),
        throwsA(
          isA<TemplateError>().having((e) => e.line, 'line', 2),
        ),
      );
    });

    test('a missing template propagates the loader error', () {
      expect(
        render({'t': "@include('nope')"}, 't'),
        throwsA(isA<TemplateError>()),
      );
    });
  });
}