# Agent Note: 首屏绕自己的中轴转

Status: implemented

## Problem

平面顺时针 30°（`2026-10-13-the-hero-comes-back-flat-and-turns-thirty.md`）
也只撑了一轮。这次的修正：「在正面立的基础上，以中间轴为中心水平旋转 30°」。
错的是旋转轴，不是角度——平面内的 `rotate()` 是把整张纸像歪照片那样倾倒，
用户要的是画面绕它自己的中央竖轴摆动，像门绕合页转。

## Decision

**`transform: rotateY(30deg)`，仅此而已。** 两条边界沿用前几轮、刻意保留：

- **不加 `perspective`。** 两轮前用户刚明确否掉 3D 侧视，没要回纵深。没有
  perspective 祖先时，`rotateY` 是正交投影：画面仍正面可读，只被压窄到
  cos30 ≈ 0.87 倍宽，左右两边对称收拢——这是平面意义上的「绕中轴旋转」。
- **不加 `scale`。** 平面那轮要 `scale(.82)`，是因为 2D 旋转会把绘制盒*撑大*
  （×1.17）；`rotateY` 是把绘制盒*缩小*（×cos），绘制盒天然比列窄——scale
  连同它的理由一起删掉。

`transform-origin` 保持默认 `50% 50%`，字面上就是「中间轴」。

## Testing

- Headless Chrome 1280×900：图像水平（无倾斜）、收窄、收在栏内。
- 真实 375px 视口的 iframe 具：`scrollWidth == clientWidth`，无元素出界。
  无 Dart 改动，六道门禁不受影响。

## Alternatives considered

**`perspective` 之下的 `rotateY(30deg)`。** 现阶段否：那会把用户刚否掉的纵深
请回来，而且 30° 下远侧退得比他们已经否掉的 20° 版更狠。已在回复里注明：
若「转动」要带纵深感，一行就能切过去。

**保留平面 `rotate(30deg)`。** 否：轴不对——那正是这一轮要修正的东西。

## Consequences

**换来。** 水平、正对观众的一屏，绕自己的中心对称收窄——要的轴，没再添纵深。

**放弃。** 正交投影的 `rotateY` 可能读作「图变窄了」而非「转动了」；压窄就是
全部可见效果。若观感不够，诚实的修法是加透视，不是加大角度。

**欠着。** 与此前相同：下次发布或手动触发 `pages.yml` 之前不上线。
