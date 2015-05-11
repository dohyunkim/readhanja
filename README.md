# readhanja

A LuaLaTeX package for semi-automatized typesetting of
Hanja-to-Hangul sound values

한자만 입력하면 한글 독음을 붙여주는 패키지. 루아텍 판.

## Usage

```
\usepackage[draft]{readhanja}
```
draft 옵션을 쓰면 모든 음가를 나열하고 현재 선택된 음가에
밑줄을 긋는다. draft 옵션은 `char` 단위를 강제한다. (see below)

```
\readhanjahangulfont{...}[...]
```
한글 독음의 식자에 쓰일 글꼴을 fontspec 방식대로 지시한다.

```
\readhanjaraise{0.5ex}
```
한글 독음을 올려 쓰는 정도를 지시한다. 0.5ex가 기본값.

```
\readhanjaunit{char}
```
읽기 단위. 독음을 글자(`char`)마다 달 것인가, 단어(`word`) 단위로
달 것인가, 를 지시한다. 단어 단위가 기본값.

```
\readhanjareading{樂}{낙,락,악,요}
```
한글 음가 DB를 수정하거나 항목을 추가한다. 참고로 `hanja2hangul.lua`는
[libhangul](https://github.com/choehwanjin/libhangul) 프로젝트의
`hanja.txt`에서 추출한 것으로 약 27,500개 한자의 음가를 가지고 있으며
음가는 가나다 순으로 정렬되어 있다.

```
\begin{readhanja} ... \end{readhanja}
```
독음 달기는 readhanja 환경 안 또는 `\readhanja` 명령 이후에만 동작한다.

```
\t2樂
```
예컨대 `樂` 글자의 여러 음가 가운데 두번째 음가를 선택한다.
위의 [draft] 옵션 참조.

## Example

```
\documentclass[ 12pt,
		% draft,
	]{article}
\usepackage[hangul]{kotex}
	\setmainhangulfont{KoPubBatang Pro Light}
	\setmainhanjafont {KoPubBatang Pro Medium}
	\setmainfallbackfont{HCR Dotum LVT}[Color=00AAAA]
\usepackage{readhanja}
	\readhanjahangulfont{KoPubBatang Pro Light}[Color=AA000080,Scale=.7]
\begin{document}
\section{騷壇赤幟引}
\begin{readhanja}
  善爲文者, 其知兵乎? 字譬則士也; 意譬則將也; 題目者, 敵國也; 掌故者, 戰\t2場墟\t2壘也;
  束字爲句, 團句成章, 猶隊伍\t2行陣也;
  韻以聲之, 詞以耀之, 猶金鼓旌旗也; 照應者, 烽\t2埈也;
  譬喩者, 遊騎也; 抑揚反復者,
  鏖戰\t3撕殺也; 破題而結束者, 先登而擒敵也;
  貴含蓄者, 不禽二毛也; 有餘音者, 振旅而凱旋也.
\end{readhanja}
\end{document}
```

## License

Publid Domain,
with an exception of `hanja2hangul.lua` which is in LGPL.
