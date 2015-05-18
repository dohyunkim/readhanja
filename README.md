# readhanja

A LuaLaTeX package for semi-automatized typesetting of
Hanja-to-Hangul sound values

한자만 입력하면 한글 독음을 붙여주는 패키지. 루아텍 판.

## Usage

```
\usepackage[draft]{readhanja}
```
draft 옵션을 쓰면 모든 음가를 나열하고 현재 선택된 음가에
밑줄을 긋는다.

```
\readhanjahangulfont{...}[...]
```
한글 독음의 식자에 쓰일 글꼴을 fontspec 방식대로 지시한다.

```
\readhanjaraise{0pt}
```
한글 독음을 올려 쓰는 정도를 지시한다.
독음 위치 `pre` 또는 `post`에서는 기본값이 0.5ex.
독음 위치 `top` 또는 `bottom`에서는 기본값이 0pt.

```
\readhanjalocate{post}
```
독음 위치. 한자 앞(`pre`)에 달 것인가, 뒤(`post`)에 달 것인가,
위(`top`)에 달 것인가, 아래(`bottom`)에 달 것인가,
를 지시한다.  기본값은 `pre`.
draft 옵션은 `pre` 또는 `post`만 인식한다.

```
\readhanjaunit{char}
```
읽기 단위. 독음을 글자(`char`)마다 달 것인가, 단어(`word`) 단위로
달 것인가, 를 지시한다. 기본값은 단어 단위.
draft 옵션은 글자 단위를 강제한다.
독음 위치 `top` 또는 `bottom`도 글자 단위를 강제한다.

```
\readhanjareading{樂}{악,낙,락,요}
```
한글 음가 DB를 수정하거나 항목을 추가한다. 참고로 `hanja2hangul.lua`는
[Unihan](http://unicode.org/charts/unihan.html)과
[libhangul](https://github.com/choehwanjin/libhangul)
프로젝트에서 추출한 것으로 약 27,800개 한자의 음가를
가지고 있다. 음가의 정렬은 Unihan의 `kHangul`을 앞세웠으나,
다만 U+6635 U+66B1 U+8D05는 `kKorean` 값을 맨 앞에 두었다.
또한 호환한자의 음가와 동일한 음가는 두번째 이하로 돌렸다.

```
\readhanjadictionary{召史}{조이}
\readhanjadictionary{召史}{}
```
한자 읽기 낱말 사전에 항목을 추가하거나 삭제할 수 있다.

```
\begin{readhanja} ... \end{readhanja}
```
독음 달기는 readhanja 환경 안 또는 `\readhanja` 명령 이후에만 동작한다.

```
\t4樂
\t`요樂
```
예컨대 樂 글자의 여러 음가 가운데 네번째 음가를 선택한다.
또는 음가를 직접 한글로 지시할 수도 있다.
readhanja 그룹 밖에서는 `\t` 명령이 다른 의미를 가질 수 있다.

```
樂^^^^fe02
```
U+FE00부터 U+FE02까지의 문자를 입력하면 직전 한자의 음가를 바꿀 수 있다.
[여기](http://unicode.org/Public/UCD/latest/ucd/StandardizedVariants.txt)를
참조.

## Example

```
\documentclass[12pt, % draft,
  ]{article}
\usepackage[hangul]{kotex}
  \setmainhangulfont{HCR Batang LVT}
\usepackage{readhanja}
  \readhanjahangulfont{HCR Batang LVT}[Color=AA0000A0,Scale=.7]
\begin{document}
\section*{大學}
\begin{readhanja}
大學之道 在明明德 在親民 在止於至善。
知止而后有定 定而后能靜 靜而后能安 安而后能慮 慮而后能得。
物有本末 事有終始 知所先後 \t2則近道矣。
古之欲明明德於天下者 先治其國 欲治其國者 先齊其家
欲齊其家者 先修其身 欲修其身者 先正其心 欲正其心者
先誠其意 欲誠其意者 先致其知 致知在格物。
物格而后知至 知至而后意誠 意誠而后心正 心正而后身修
身修而后家齊 家齊而后國治 國治而后天下平。
自天子以至於庶人 壹是皆以修身為本。
其本亂而末治者否矣 其所厚者薄 而其所薄者厚 未之有也。
\end{readhanja}
\end{document}
```

## License

Public Domain,
with an exception of `hanja2hangul.lua` which is in LGPL.
