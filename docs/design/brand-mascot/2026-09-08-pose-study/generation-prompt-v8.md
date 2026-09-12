# 第八版：在第七版基础上加强书写专注感

后续反馈：用户表示“基本满意”，第八版成为静态设计基准；下述“待验收”为生成当时的记录，当前进入 Rive 动作原型阶段。

用户重新附上第七版图，评价“这一版接近我需要的方向”，并进一步明确“书写表情还需要更专注”。第七版作为当前方向基准，尚未视为最终定稿。

本轮通过内置 image_gen 进行局部编辑：只增加书写眼线的内倾程度、略收紧眼距，保留两条圆端浅弧的风格及其他角色部件。第六版右侧流汗仍为明确认可基准。

输出：`idle-writing-concerned-v8.png`。视觉检查：书写眼线的两端高低差更明显、眼距略收紧，仍为两条圆端连续线；大圆手、笔、圆球主体及右侧流汗在视觉上保留。没有新增五官。书写表情待用户验收；未做像素不变断言或实际 40pt 验证。生成原图只复制保存，无后处理。

## 完整编辑提示词

Use case: precise-object-edit.
Input image is the exact edit target: a three-pose black sphere mascot sheet. The user likes this design direction, but wants the CENTER WRITING EXPRESSION to feel more concentrated.

Change ONLY the two white eye strokes of the middle writing mascot. Keep the left idle mascot and the right sweating mascot completely unchanged. Preserve every body silhouette, the big round ball hands, ivory pencil, scribble, background, scale, shading and composition.

Retain the current minimal eye design, and refine it subtly:
- Exactly two separate simple white rounded-end eye strokes, one smooth continuous shallow curve for each eye.
- Slightly narrow the space between the eyes, about 20 percent less than currently.
- Lower the INNER ends a little further so the pair has a clearer but restrained inward downward inclination. Aim for about a 20–25 degree inclination from horizontal rather than the current almost horizontal far eye.
- Make both eye strokes feel purposefully narrowed and directed down toward the writing area: intent, absorbed, industrious, seriously focused on this little task. Preserve subtle near/far perspective and gently wrap the strokes over the spherical face.
- Preserve approximately their current substantial length and thickness. No tiny dots or shortened stubs. Use supple gentle curvature, without a happy arch.
- This is a SMALL refinement of the attached writing face, not a new facial design. Concentration should be clearer, while the character remains soft and likeable.

Do NOT add or bring back angular bent eyes, hooked vertical tails, V-shaped chevron eye symbols, sharp corners, additional eyebrows, pupils, mouth, nose, cheek marks, tears or extra stress lines. Avoid fury, scowling, aggression, exhaustion or sleepy relaxed closed eyes. No additional facial elements. Do not change the right character's approved squeezed eyes or sweat drop.
Output the same landscape three-pose reference sheet with the same white background, no labels or text.
