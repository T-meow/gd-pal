/* Add an image room here and place its SVG/PNG/JPEG beside the other assets.
   A future 3D renderer can register a different kind without changing the UI. */
window.PAL_ROOMS = [
  {
    id: "night-study", name: "夜间书房", english: "THE NIGHT STUDY", kind: "image",
    background: "assets/rooms/night-study.svg", thumbnail: "assets/rooms/night-study.svg",
    time: "22:16", accent: "#aac6e7", mood: "安静 · 阅读 · 慢慢聊",
    description: "窗外是沉静的蓝，手边的茶还温热。",
    caption: "夜深了，这盏灯为你留着。", context: "一盏灯，一段还没说完的话。",
    arrival: "她把书签放进书里，为你挪出身旁的位置。",
    reply: "那就在这里坐一会儿吧。书可以慢慢读，今天的事也可以慢慢说。我听着呢。"
  },
  {
    id: "warm-bedroom", name: "暖光卧室", english: "A SOFTER EVENING", kind: "image",
    background: "assets/rooms/warm-bedroom.svg", thumbnail: "assets/rooms/warm-bedroom.svg",
    time: "23:08", accent: "#e1bc96", mood: "温暖 · 放松 · 晚安",
    description: "把灯调暗一点，把今天轻轻放下来。",
    caption: "今天也辛苦了，慢慢放松下来吧。", context: "把疲惫交给夜晚，把时间留给彼此。",
    arrival: "她把柔软的抱枕递给你，又调暗了一点床头灯。",
    reply: "嗯，今天已经做得很好了。不用把每件事都想明白，靠着休息一下吧。等你困了，我再轻轻说晚安。"
  },
  {
    id: "rainy-lounge", name: "雨夜客厅", english: "WHEN THE RAIN FALLS", kind: "image",
    background: "assets/rooms/rainy-lounge.svg", thumbnail: "assets/rooms/rainy-lounge.svg",
    time: "21:42", accent: "#9cc8c4", mood: "雨声 · 热茶 · 心事",
    description: "雨落在玻璃上，世界只剩下我们。",
    caption: "外面在下雨，幸好你在这里。", context: "窗外的雨声，刚好填满停顿。",
    arrival: "她听着窗外的雨，把另一杯热茶推到你面前。",
    reply: "听，雨好像又小了一点。你可以把心事留在这杯热茶旁边，我陪你等它慢慢变轻。今晚，我们不赶时间。"
  }
];
