// Copyright 2017 Google Inc. Use of this source code is governed by an
// MIT-style license that can be found in the LICENSE file or at
// https://opensource.org/licenses/MIT.

@TestOn('node')
@Tags(const ['node'])

import 'dart:convert';
import 'dart:js';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'package:sass/src/node/utils.dart';

import 'ensure_npm_package.dart';
import 'hybrid.dart';
import 'node_api/api.dart';
import 'node_api/intercept_stdout.dart';
import 'node_api/utils.dart';

String sassPath;

void main() {
  setUpAll(ensureNpmPackage);
  useSandbox();

  setUp(() async {
    sassPath = p.join(sandbox, 'test.scss');
    await writeTextFile(sassPath, 'a {b: c}');
  });

  group("renderSync()", () {
    test("renders a file", () {
      expect(renderSync(new RenderOptions(file: sassPath)),
          equalsIgnoringWhitespace('a { b: c; }'));
    });

    test("renders a file from a relative path", () {
      runTestInSandbox();
      expect(renderSync(new RenderOptions(file: 'test.scss')),
          equalsIgnoringWhitespace('a { b: c; }'));
    });

    test("renders a file with the indented syntax", () async {
      var indentedPath = p.join(sandbox, 'test.sass');
      await writeTextFile(indentedPath, 'a\n  b: c');
      expect(renderSync(new RenderOptions(file: indentedPath)),
          equalsIgnoringWhitespace('a { b: c; }'));
    });

    test("supports relative imports for a file", () async {
      var importerPath = p.join(sandbox, 'importer.scss');
      await writeTextFile(importerPath, '@import "test"');
      expect(renderSync(new RenderOptions(file: importerPath)),
          equalsIgnoringWhitespace('a { b: c; }'));
    });

    // Regression test for #284
    test("supports relative imports for a file from a relative path", () async {
      await createDirectory(p.join(sandbox, 'subdir'));

      var importerPath = p.join(sandbox, 'subdir/importer.scss');
      await writeTextFile(importerPath, '@import "../test"');

      runTestInSandbox();
      expect(renderSync(new RenderOptions(file: 'subdir/importer.scss')),
          equalsIgnoringWhitespace('a { b: c; }'));
    });

    test("supports absolute path imports", () async {
      expect(
          renderSync(new RenderOptions(
              // Node Sass parses imports as paths, not as URLs, so the absolute
              // path should work here.
              data: '@import "${sassPath.replaceAll('\\', '\\\\')}"')),
          equalsIgnoringWhitespace('a { b: c; }'));
    });

    test("renders a string", () {
      expect(renderSync(new RenderOptions(data: "a {b: c}")),
          equalsIgnoringWhitespace('a { b: c; }'));
    });

    test("one of data and file must be set", () {
      var error = renderSyncError(new RenderOptions());
      expect(error.toString(),
          contains('Either options.data or options.file must be set.'));
    });

    test("supports load paths", () {
      expect(
          renderSync(new RenderOptions(
              data: "@import 'test'", includePaths: [sandbox])),
          equalsIgnoringWhitespace('a { b: c; }'));
    });

    // Regression test for #314
    test(
        "a file imported through a relative load path supports relative "
        "imports", () async {
      var subDir = p.join(sandbox, 'sub');
      await createDirectory(subDir);
      await writeTextFile(p.join(subDir, '_test.scss'), '@import "other"');

      await writeTextFile(p.join(subDir, '_other.scss'), 'x {y: z}');

      expect(
          renderSync(new RenderOptions(
              data: "@import 'sub/test'", includePaths: [p.relative(sandbox)])),
          equalsIgnoringWhitespace('x { y: z; }'));
    });

    test("can render the indented syntax", () {
      expect(
          renderSync(
              new RenderOptions(data: "a\n  b: c", indentedSyntax: true)),
          equalsIgnoringWhitespace('a { b: c; }'));
    });

    test("the indented syntax flag takes precedence over the file extension",
        () async {
      var scssPath = p.join(sandbox, 'test.scss');
      await writeTextFile(scssPath, 'a\n  b: c');
      expect(
          renderSync(new RenderOptions(file: scssPath, indentedSyntax: true)),
          equalsIgnoringWhitespace('a { b: c; }'));
    });

    test("supports the expanded output style", () {
      expect(
          renderSync(
              new RenderOptions(file: sassPath, outputStyle: 'expanded')),
          equals('a {\n  b: c;\n}'));
    });

    test("doesn't support other output styles", () {
      var error = renderSyncError(
          new RenderOptions(file: sassPath, outputStyle: 'nested'));
      expect(error.toString(), contains('Unsupported output style "nested".'));
    });

    test("allows tab indentation", () {
      expect(renderSync(new RenderOptions(file: sassPath, indentType: 'tab')),
          equals('''
a {
\t\tb: c;
}'''));
    });

    test("allows unknown indentation names", () {
      expect(renderSync(new RenderOptions(file: sassPath, indentType: 'asdf')),
          equals('''
a {
  b: c;
}'''));
    });

    group("linefeed allows", () {
      test("cr", () {
        expect(renderSync(new RenderOptions(file: sassPath, linefeed: 'cr')),
            equals('a {\r  b: c;\r}'));
      });

      test("crlf", () {
        expect(renderSync(new RenderOptions(file: sassPath, linefeed: 'crlf')),
            equals('a {\r\n  b: c;\r\n}'));
      });

      test("lfcr", () {
        expect(renderSync(new RenderOptions(file: sassPath, linefeed: 'lfcr')),
            equals('a {\n\r  b: c;\n\r}'));
      });

      test("unknown names", () {
        expect(renderSync(new RenderOptions(file: sassPath, linefeed: 'asdf')),
            equals('a {\n  b: c;\n}'));
      });
    });

    group("indentWidth allows", () {
      test("a number", () {
        expect(renderSync(new RenderOptions(file: sassPath, indentWidth: 10)),
            equals('''
a {
          b: c;
}'''));
      });

      test("a string", () {
        expect(renderSync(new RenderOptions(file: sassPath, indentWidth: '1')),
            equals('''
a {
 b: c;
}'''));
      });
    });

    test("emits warnings on stderr", () {
      expect(
          const LineSplitter().bind(interceptStderr()),
          emitsInOrder([
            "WARNING: aw beans",
            "    stdin 1:1  root stylesheet",
          ]));

      expect(renderSync(new RenderOptions(data: "@warn 'aw beans'")), isEmpty);
    });

    test("emits debug messages on stderr", () {
      expect(const LineSplitter().bind(interceptStderr()),
          emits("stdin:1 DEBUG: what the heck"));

      expect(renderSync(new RenderOptions(data: "@debug 'what the heck'")),
          isEmpty);
    });

    group("with both data and file", () {
      test("uses the data parameter as the source", () {
        expect(renderSync(new RenderOptions(data: "x {y: z}", file: sassPath)),
            equalsIgnoringWhitespace('x { y: z; }'));
      });

      test("doesn't require the file path to exist", () {
        expect(
            renderSync(new RenderOptions(
                data: "x {y: z}", file: p.join(sandbox, 'non-existent.scss'))),
            equalsIgnoringWhitespace('x { y: z; }'));
      });

      test("imports relative to the file path", () async {
        await writeTextFile(p.join(sandbox, 'importee.scss'), 'x {y: z}');
        expect(
            renderSync(
                new RenderOptions(data: "@import 'importee'", file: sassPath)),
            equalsIgnoringWhitespace('x { y: z; }'));
      });

      test("reports errors from the file path", () {
        var error =
            renderSyncError(new RenderOptions(data: "x {y: }", file: sassPath));
        expect(
            error.toString(),
            equals("Error: Expected expression.\n"
                "  $sassPath 1:7  root stylesheet"));
      });
    });

    group("the result object", () {
      test("includes the filename", () {
        var result = sass.renderSync(new RenderOptions(file: sassPath));
        expect(result.stats.entry, equals(sassPath));
      });

      test("includes data without a filename", () {
        var result = sass.renderSync(new RenderOptions(data: 'a {b: c}'));
        expect(result.stats.entry, equals('data'));
      });

      test("includes timing information", () {
        var result = sass.renderSync(new RenderOptions(file: sassPath));
        expect(result.stats.start, const TypeMatcher<int>());
        expect(result.stats.end, const TypeMatcher<int>());
        expect(result.stats.start, lessThanOrEqualTo(result.stats.end));
        expect(result.stats.duration,
            equals(result.stats.end - result.stats.start));
      });

      group("has includedFiles which", () {
        test("contains the root path if available", () {
          var result = sass.renderSync(new RenderOptions(file: sassPath));
          expect(result.stats.includedFiles, equals([sassPath]));
        });

        test("doesn't contain the root path if it's not available", () {
          var result = sass.renderSync(new RenderOptions(data: 'a {b: c}'));
          expect(result.stats.includedFiles, isEmpty);
        });

        test("contains imported paths", () async {
          var importerPath = p.join(sandbox, 'importer.scss');
          await writeTextFile(importerPath, '@import "test"');

          var result = sass.renderSync(new RenderOptions(file: importerPath));
          expect(result.stats.includedFiles,
              unorderedEquals([importerPath, sassPath]));
        });

        test("only contains each path once", () async {
          var importerPath = p.join(sandbox, 'importer.scss');
          await writeTextFile(importerPath, '@import "test"; @import "test";');

          var result = sass.renderSync(new RenderOptions(file: importerPath));
          expect(result.stats.includedFiles,
              unorderedEquals([importerPath, sassPath]));
        });
      });
    });

    group("the error object", () {
      RenderError error;
      group("for a parse error in a file", () {
        setUp(() async {
          await writeTextFile(sassPath, "a {b: }");
          error = renderSyncError(new RenderOptions(file: sassPath));
        });

        test("is a JS Error", () async {
          expect(isJSError(error), isTrue);
        });

        test("has a useful toString() and message", () async {
          expect(
              error,
              toStringAndMessageEqual("Expected expression.\n"
                  "  $sassPath 1:7  root stylesheet"));
        });

        test("has a useful formatted message", () async {
          expect(
              error.formatted,
              "Error: Expected expression.\n"
              "a {b: }\n"
              "      ^\n"
              "  $sassPath 1:7  root stylesheet");
        });

        test("sets the line, column, and filename", () {
          expect(error.line, equals(1));
          expect(error.column, equals(7));
          expect(error.file, equals(sassPath));
        });
      });

      group("for a parse error in a string", () {
        setUp(() {
          error = renderSyncError(new RenderOptions(data: "a {b: }"));
        });

        test("is a JS Error", () async {
          expect(isJSError(error), isTrue);
        });

        test("has a useful toString() and message", () {
          expect(
              error,
              toStringAndMessageEqual("Expected expression.\n"
                  "  stdin 1:7  root stylesheet"));
        });

        test("has a useful formatted message", () {
          expect(
              error.formatted,
              "Error: Expected expression.\n"
              "a {b: }\n"
              "      ^\n"
              "  stdin 1:7  root stylesheet");
        });

        test("sets the line, column, and filename", () {
          expect(error.line, equals(1));
          expect(error.column, equals(7));
          expect(error.file, equals("stdin"));
        });
      });

      group("for a runtime error in a file", () {
        setUp(() async {
          await writeTextFile(sassPath, "a {b: 1 % a}");
          error = renderSyncError(new RenderOptions(file: sassPath));
        });

        test("has a useful toString() and message", () {
          expect(
              error,
              toStringAndMessageEqual('Undefined operation "1 % a".\n'
                  '  $sassPath 1:7  root stylesheet'));
        });

        test("has a useful formatted message", () async {
          expect(
              error.formatted,
              'Error: Undefined operation "1 % a".\n'
              'a {b: 1 % a}\n'
              '      ^^^^^\n'
              '  $sassPath 1:7  root stylesheet');
        });

        test("sets the line, column, and filename", () {
          expect(error.line, equals(1));
          expect(error.column, equals(7));
          expect(error.file, equals(sassPath));
        });
      });

      group("for a runtime error in a string", () {
        setUp(() {
          error = renderSyncError(new RenderOptions(data: "a {b: 1 % a}"));
        });

        test("has a useful toString() and message", () {
          expect(
              error,
              toStringAndMessageEqual('Undefined operation "1 % a".\n'
                  '  stdin 1:7  root stylesheet'));
        });

        test("has a useful formatted message", () {
          expect(
              error.formatted,
              'Error: Undefined operation "1 % a".\n'
              'a {b: 1 % a}\n'
              '      ^^^^^\n'
              '  stdin 1:7  root stylesheet');
        });

        test("sets the line, column, and filename", () {
          expect(error.line, equals(1));
          expect(error.column, equals(7));
          expect(error.file, equals("stdin"));
        });
      });
    });

    group("when called with a raw JS collection", () {
      test("for includePaths", () {
        expect(
            renderSyncJS({
              "data": "@import 'test'",
              "includePaths": [sandbox]
            }),
            equalsIgnoringWhitespace('a { b: c; }'));
      });

      // Regression test for #412
      test("for includePaths with an importer", () {
        expect(
            renderSyncJS({
              "data": "@import 'test'",
              "includePaths": [sandbox],
              "importer": allowInterop((url, prev) => null)
            }),
            equalsIgnoringWhitespace('a { b: c; }'));
      });
    });
  });

  group("render()", () {
    test("renders a file", () async {
      expect(await render(new RenderOptions(file: sassPath)),
          equalsIgnoringWhitespace('a { b: c; }'));
    });

    test("throws an error that has a useful toString", () async {
      await writeTextFile(sassPath, 'a {b: }');

      var error = await renderError(new RenderOptions(file: sassPath));
      expect(
          error.toString(),
          equals("Error: Expected expression.\n"
              "  $sassPath 1:7  root stylesheet"));
    });
  },
      // render() and renderError() use Zone.bindBinaryCallbackGuarded(), which
      // is only available on Dart 2.
      tags: "dart2");
}
