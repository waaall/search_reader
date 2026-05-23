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

  group('findMatchOffset', () {
    test('找到关键词时返回原文位置', () {
      const content = '夜色如水，月光在屋檐上铺成薄薄一层霜。';
      expect(findMatchOffset(content, '月光'), content.indexOf('月光'));
    });

    test('多关键词优先用最长的找位置', () {
      const content = '城门外，李寻欢的飞刀已经出鞘。';
      // "李" 与 "李寻欢" 都在原文中，应取最长的 "李寻欢" 的位置
      expect(findMatchOffset(content, '李 李寻欢'), content.indexOf('李寻欢'));
    });

    test('整词不连续出现时退化用第一个 bigram 定位', () {
      // "你好世" 不在原文连续出现，但 bigram "你好" 在
      // FTS 按 bigram AND 命中也可能落到这种情况
      const content = '前面是你好的内容，后面有世界两个字。';
      expect(findMatchOffset(content, '你好世'), content.indexOf('你好'));
    });

    test('完全没找到时返回 0', () {
      const content = '这是一段不含关键词的文字。';
      expect(findMatchOffset(content, '武功'), 0);
    });

    test('空 query 返回 0', () {
      expect(findMatchOffset('任意内容', ''), 0);
      expect(findMatchOffset('任意内容', '   '), 0);
    });

    test('关键词在原文首位时返回 0', () {
      const content = '月光下的小镇安静。';
      expect(findMatchOffset(content, '月光'), 0);
    });
  });
}
