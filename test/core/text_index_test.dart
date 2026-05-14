import 'package:flutter_test/flutter_test.dart';
import 'package:search_reader/core/db/text_index.dart';

void main() {
  group('toBigramTokens', () {
    test('中文按相邻 2 字符切分', () {
      expect(toBigramTokens('你好世界'), '你好 好世 世界');
    });

    test('单字符段保留为 1-gram', () {
      expect(toBigramTokens('a'), 'a');
    });

    test('空白归一化，跨段不产生 bigram', () {
      expect(toBigramTokens('你好  世界'), '你好 世界');
      expect(toBigramTokens('a\nbc'), 'a bc');
    });

    test('空字符串返回空', () {
      expect(toBigramTokens(''), '');
      expect(toBigramTokens('   '), '');
    });
  });

  group('toBigramQuery', () {
    test('2 字符 → 单 bigram phrase', () {
      expect(toBigramQuery('你好'), '"你好"');
    });

    test('3 字符 → 紧邻短语', () {
      expect(toBigramQuery('你好世'), '("你好" + "好世")');
    });

    test('4 字符 → 三个 bigram 紧邻', () {
      expect(toBigramQuery('你好世界'), '("你好" + "好世" + "世界")');
    });

    test('多关键词空格分隔 → AND 连接', () {
      expect(toBigramQuery('剑客 武功'), '"剑客" AND "武功"');
    });

    test('1 字符也保留（虽然命中概率低）', () {
      expect(toBigramQuery('好'), '"好"');
    });

    test('FTS5 特殊字符被清掉', () {
      expect(toBigramQuery('你好"世界'), '"你好" AND "世界"');
    });

    test('空输入返回空串', () {
      expect(toBigramQuery(''), '');
      expect(toBigramQuery('   '), '');
    });
  });

  group('makeSnippet', () {
    test('找到关键词时高亮', () {
      const content = '夜色如水，月光在屋檐上铺成薄薄一层霜。她合上书本，听到风穿过竹林的声音。';
      final s = makeSnippet(content, '月光');
      expect(s.contains('<mark>月光</mark>'), true);
    });

    test('未找到关键词时返回开头摘要', () {
      const content = '这是一段不含关键词的文字。';
      final s = makeSnippet(content, '武功');
      expect(s.contains('<mark>'), false);
    });

    test('多关键词优先用最长的找位置', () {
      const content = '城门外，李寻欢的飞刀已经出鞘。';
      final s = makeSnippet(content, '李 李寻欢');
      expect(s.contains('<mark>李寻欢</mark>'), true);
    });
  });
}
