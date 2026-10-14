const fs = require('node:fs');
const path = require('node:path');
const out = __dirname;
const project = path.resolve(out, '../..');
const C = { bg:'#10151d', top:'#121820', panel:'#151d28', surface:'#1b2736', field:'#101925', line:'#2b394b', ink:'#edf2f8', muted:'#99abbe', faint:'#71869c', blue:'#acc9e7', green:'#a4c6b6', warm:'#dfc39f', red:'#d7a1a7' };
const escape = s => String(s).replaceAll('&','&amp;').replaceAll('<','&lt;').replaceAll('>','&gt;').replaceAll('"','&quot;');
const asset = p => 'data:image/svg+xml;base64,' + fs.readFileSync(path.join(project, p)).toString('base64');
const room = asset('assets/rooms/night-study.svg');
const avatar = asset('design/desktop-ui-prototype/assets/character-avatar.svg');
const portrait = asset('design/desktop-ui-prototype/assets/character-portrait.svg');
const rect = (x,y,w,h,fill=C.surface,r=10,stroke='none',extra='') => `<rect x="${x}" y="${y}" width="${w}" height="${h}" rx="${r}" fill="${fill}" stroke="${stroke}" ${extra}/>`;
const text = (x,y,s,size=14,fill=C.ink,weight=400,extra='') => `<text x="${x}" y="${y}" font-size="${size}" fill="${fill}" font-weight="${weight}" ${extra}>${escape(s)}</text>`;
const line = (x1,y1,x2,y2,stroke=C.line,extra='') => `<path d="M${x1} ${y1}H${x2}" fill="none" stroke="${stroke}" ${extra}/>`;
const dot = (x,y,color=C.green,r=3) => `<circle cx="${x}" cy="${y}" r="${r}" fill="${color}"/>`;
const image = (href,x,y,w,h,extra='') => `<image href="${href}" x="${x}" y="${y}" width="${w}" height="${h}" preserveAspectRatio="xMidYMid slice" ${extra}/>`;
const paths = {
  chat:'M5 4h14a2 2 0 0 1 2 2v10a2 2 0 0 1-2 2H9l-5 3v-3H3V6a2 2 0 0 1 2-2Z',
  user:'M16 7a4 4 0 1 1-8 0 4 4 0 0 1 8 0ZM4 21v-2a8 8 0 0 1 16 0v2',
  book:'M12 5c-3-2-6-2-10-1v15c4-1 7-1 10 1 3-2 6-2 10-1V4c-4-1-7-1-10 1Zm0 0v15',
  memory:'M12 3a9 9 0 1 1-8.2 5.2M3 3v6h6M12 7v5l3 2',
  gear:'m9 3-1 3-3 1-2 4 2 2 1 3 3 1 2 3h3l2-3 3-1 1-3 2-2-2-4-3-1-1-3H9Zm6 9a3 3 0 1 1-6 0 3 3 0 0 1 6 0Z',
  search:'M17 10a7 7 0 1 1-14 0 7 7 0 0 1 14 0Zm-2 5 6 6',
  arrow:'M4 12h15m-6-6 6 6-6 6',
  up:'M6 18 18 6M7 6h11v11',
  down:'m6 9 6 6 6-6',
  close:'m6 6 12 12M18 6 6 18',
  check:'m5 12 4 4L19 6',
  plus:'M12 4v16M4 12h16',
  spark:'m12 2 2.5 7.5L22 12l-7.5 2.5L12 22l-2.5-7.5L2 12l7.5-2.5L12 2Z',
  eye:'M2 12s4-7 10-7 10 7 10 7-4 7-10 7S2 12 2 12Zm13 0a3 3 0 1 1-6 0 3 3 0 0 1 6 0Z',
  link:'M9 15 15 9M8 17l-1 1a4 4 0 0 1-6-6l5-5a4 4 0 0 1 6 0m0 10a4 4 0 0 0 6 0l5-5a4 4 0 0 0-6-6l-1 1',
  room:'m3 10 9-7 9 7v11H3V10Zm6 11v-8h6v8',
  desktop:'M3 4h18v13H3V4Zm5 17h8m-4-4v4',
  sound:'M4 9h4l5-5v16l-5-5H4V9Zm12-2a7 7 0 0 1 0 10m3-13a11 11 0 0 1 0 16',
  more:'M5 12h.1M12 12h.1M19 12h.1',
  rain:'M7 13a5 5 0 1 1 3-9 4 4 0 0 1 7 3 3 3 0 1 1 1 6H7Zm0 4-1 3m6-3-1 3m6-3-1 3',
  clock:'M21 12a9 9 0 1 1-18 0 9 9 0 0 1 18 0ZM12 6v6l4 2',
  shield:'m12 3 8 3v6c0 5-8 9-8 9s-8-4-8-9V6l8-3Z',
};
function icon(name,x,y,size=20,color=C.muted){ return `<g transform="translate(${x} ${y}) scale(${size/24})" fill="none" stroke="${color}" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"><path d="${paths[name] || paths.spark}"/></g>`; }
function pill(x,y,w,label,color=C.blue,fill='#25374b'){return rect(x,y,w,25,fill,6)+text(x+w/2,y+17,label,11,color,400,'text-anchor="middle"');}
function button(x,y,w,label,primary=false,kind='') {return rect(x,y,w,40,primary?C.blue:'#1c2939',8,primary?'none':'#34455a')+(kind?icon(kind,x+13,y+11,17,primary?'#172433':C.blue):'')+text(x+w/2+(kind?7:0),y+26,label,14,primary?'#142536':C.ink,primary?600:400,'text-anchor="middle"');}
function toggle(x,y,on=true){return rect(x,y,43,24,on?'#8fb7d9':'#344358',12)+dot(x+(on?31:12),y+12,on?'#f3f7fb':'#a2afbe',8);}
function field(x,y,w,label,value,option=false){return text(x,y,label,13,C.muted)+rect(x,y+13,w,45,C.field,8,C.line)+text(x+15,y+42,value,14,C.ink)+(option?icon('down',x+w-32,y+27,18):'');}
function source(x,y,label='查看原对话'){return icon('up',x,y-12,15,C.blue)+text(x+23,y,label,12,C.blue);}
function svg(title,body,w=1440,h=900){return `<?xml version="1.0" encoding="UTF-8"?>\n<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="${w}" height="${h}" viewBox="0 0 ${w} ${h}" role="img" aria-label="${escape(title)}"><title>${escape(title)}</title><defs><linearGradient id="panel" x1="0" y1="0" x2="1" y2="1"><stop stop-color="#192330"/><stop offset="1" stop-color="#121b27"/></linearGradient><linearGradient id="portrait" x1="0" y1="0" x2="0" y2="1"><stop stop-color="#30455b"/><stop offset="1" stop-color="#172434"/></linearGradient><radialGradient id="glow"><stop stop-color="#426385" stop-opacity=".24"/><stop offset="1" stop-color="#10151d" stop-opacity="0"/></radialGradient><clipPath id="avatar-clip"><circle cx="32" cy="93" r="18"/></clipPath><clipPath id="portrait-clip"><rect x="164" y="256" width="242" height="421" rx="12"/></clipPath></defs><g font-family="Microsoft YaHei UI,Microsoft YaHei,Segoe UI,sans-serif">${body}</g></svg>\n`;}
function shell(active='memory') {
  let s=rect(0,0,1440,900,C.bg,0)+image(room,64,56,1376,844,'opacity=".3"')+rect(64,56,1376,844,'#080e17',0,'none','opacity=".63"')+`<ellipse cx="670" cy="420" rx="750" ry="560" fill="url(#glow)"/>`;
  s+=rect(0,0,1440,56,C.top,0)+line(0,55,1440,55,'#263344')+icon('spark',19,18,22,C.blue)+text(55,35,'GD PAL',15,C.ink,600,'letter-spacing="2"')+text(157,34,'与你在一起',11,C.faint);
  s+=rect(597,10,246,35,'#0d141d',8,'#263344');
  ['通话','房间','桌宠'].forEach((v,i)=>{if(i===0)s+=rect(601+i*80,14,78,27,'#263548',5);s+=icon(['chat','room','desktop'][i],613+i*80,20,14,i===0?C.blue:C.faint)+text(635+i*80,31,v,12,i===0?C.ink:C.muted);});
  s+=pill(1163,17,83,'界面预览',C.warm,'#302e2c')+line(1294,28,1305,28,C.muted)+rect(1332,21,11,11,'none',1,C.muted)+icon('close',1372,18,19,C.muted);
  s+=rect(0,56,64,844,C.top,0)+`<path d="M63 56V900" stroke="#263344"/>`+image(avatar,14,75,36,36,'clip-path="url(#avatar-clip)"')+dot(45,108,C.green,3);
  const nav=[['chat','对话'],['user','角色'],['book','剧情'],['memory','回忆']];
  nav.forEach(([name,label],i)=>{let y=140+i*75;if(name===active)s+=rect(7,y-7,50,61,'#26374a',9)+rect(1,y+3,3,36,C.blue,1);s+=icon(name,22,y+1,21,name===active?C.blue:C.faint)+text(32,y+44,label,10,name===active?C.ink:C.faint,400,'text-anchor="middle"');});
  s+=icon('plus',22,475,21,C.faint)+text(32,513,'添加',10,C.faint,400,'text-anchor="middle"');
  if(active==='gear')s+=rect(7,802,50,65,'#26374a',9)+rect(1,813,3,35,C.blue,1);
  s+=icon('gear',22,815,21,active==='gear'?C.blue:C.faint)+text(32,858,'设置',10,active==='gear'?C.ink:C.faint,400,'text-anchor="middle"');
  s+=text(96,866,'夜间书房',11,'#506175')+text(1349,866,'示例内容',10,'#506175',400,'text-anchor="end"');
  s+=rect(128,95,1184,760,'#030a13',18,'none','opacity=".32"')+rect(128,88,1184,760,'url(#panel)',16,'#344258');
  return s;
}
function heading(title,subtitle){return text(164,134,title,25,C.ink,600)+text(164,161,subtitle,12,C.muted)+rect(1249,110,36,36,'#202b3a',8)+icon('close',1257,118,20);}
function tabs(labels,selected,widths){let s='',x=164;labels.forEach((label,i)=>{let w=widths?widths[i]:110;if(i===selected)s+=rect(x,191,w,34,'#2a3b50',7)+rect(x+18,234,w-36,2,C.blue,1);s+=text(x+w/2,214,label,13,i===selected?C.ink:C.muted,i===selected?600:400,'text-anchor="middle"');x+=w+9;});return s+line(164,236,1276,236);}
function footer(note,primary='保存设置',cancel='取消'){return line(164,771,1276,771)+text(164,813,note,12,C.faint)+button(986,790,111,cancel)+button(1111,790,165,primary,true);}
function connections(){
  let s=shell('gear')+heading('连接设置','为聊天、记忆与声音选择合适的模型服务。')+tabs(['聊天模型','记忆整理','记忆检索','语音服务'],2,[115,115,115,115]);
  s+=rect(164,258,668,84,'#233448',11,'#3b526a')+icon('spark',185,281,24,C.blue)+text(226,289,'更容易想起旧事',18,C.ink,600)+text(226,315,'即使用不同的说法，也能找到以前聊过的经历。',13,C.muted)+toggle(764,281,true);
  s+=field(164,376,668,'检索模型（Embedding）','embedding-model');
  s+=field(164,474,668,'API 地址','http://127.0.0.1:8001/v1');
  s+=text(164,551,'API Key',13,C.muted)+rect(164,564,668,45,C.field,8,C.line)+text(180,593,'••••••••••••••••••••••••',15,C.muted,400,'letter-spacing="2"')+icon('eye',795,577,20,C.muted);
  s+=rect(164,636,17,17,'#121c2a',4,'#5b718a')+text(192,650,'在此电脑记住 Key',13,C.ink)+text(164,681,'未勾选时，Key 仅在本次运行中使用。',12,C.faint);
  s+=icon('link',164,718,17,C.faint)+text(191,732,'检索模型独立配置，可与聊天模型使用不同服务。',12,C.muted);
  s+=rect(864,258,412,155,'#1c2b3a',11,'#31455a')+text(886,288,'当前检索方式',12,C.muted)+text(886,325,'语义 + 关键词',23,C.ink,500)+dot(891,354)+text(903,359,'已配置',12,C.green)+text(886,389,'在当前存档中寻找相关的旧经历与长期记忆。',12,C.muted);
  s+=rect(864,435,412,246,'#172331',11,C.line)+icon('memory',887,455,20,C.warm)+text(918,471,'换个说法，也能想起',16,C.ink,500);
  s+=rect(886,493,368,49,'#24364a',8)+text(903,523,'“那次我们躲雨的晚上……”',14,C.blue);
  s+=icon('down',1058,551,19,C.faint)+rect(886,581,368,70,'#1c2b3b',8,'#34485d')+icon('rain',903,601,24,C.warm)+text(942,609,'森林书屋里的雨夜',15,C.ink,500)+text(942,633,'来自以前的共同经历',12,C.muted);
  s+=button(864,710,174,'更新记忆索引',false,'memory')+text(1055,735,'最近更新已完成',12,C.green);
  s+=footer('未开启语义检索时，仍可使用关键词查找。');
  return svg('GD Pal · 记忆检索连接设置',s);
}
const memoryTabs=['查找回忆','当前状态','近期经历','长期记忆','相处档案','经历与设定'];
function memoryHeader(selected){return heading('回忆手册','凛  /  日常陪伴  ·  当前记忆存档')+tabs(memoryTabs,selected,[116,110,110,110,110,124])+text(1090,214,'自动整理',12,C.muted)+toggle(1156,194)+icon('more',1247,197,23,C.muted);}
function resultCard(y,title,date,badge,badgeColor,summary,selected=false){
  return rect(164,y,390,131,selected?'#26394e':'#1a2635',10,selected?'#678bab':'#2b3a4d')+(selected?rect(164,y+15,3,101,C.blue,1):'')+
    text(184,y+30,title,16,C.ink,selected?600:500)+text(534,y+30,date,11,C.faint,400,'text-anchor="end"')+pill(184,y+46,84,badge,badgeColor,selected?'#30485d':'#253447')+text(184,y+99,summary,12,C.muted);
}
function recall(){
  let s=shell('memory')+memoryHeader(0);
  s+=rect(164,259,899,49,C.field,9,'#526f8c')+icon('search',181,273,20,C.blue)+text(218,289,'还记得那次下雨吗',16,C.ink)+rect(974,265,82,37,'#a9c7e5',6)+text(1015,289,'查找',13,'#17283a',600,'text-anchor="middle"');
  s+=pill(1081,270,195,'语义检索已开启',C.green,'#243b3a')+text(164,338,'找到 3 条相关回忆',13,C.muted)+text(1114,338,'当前存档 · 所有会话',12,C.muted)+icon('down',1254,323,18,C.muted);
  s+=resultCard(356,'书屋里的那个雨夜','10月04日','剧情经历',C.warm,'一起躲雨，读完了窗边的那本书。',true);
  s+=resultCard(499,'周五下班时的暴雨','10月09日','你的陈述',C.blue,'你提过那天忘了带伞，回来时淋湿了。');
  s+=resultCard(642,'喜欢窗外的雨声','10月10日','长期偏好',C.green,'你说安静地听雨会让自己放松下来。');
  s+=rect(582,356,694,353,'#192635',12,C.line)+pill(607,378,86,'剧情经历',C.warm,'#3a3531')+text(712,395,'你与凛的共同故事',12,C.muted);
  s+=text(607,441,'书屋里的那个雨夜',24,C.ink,600)+text(607,478,'那晚你们在森林书屋躲雨，一起读完了窗边的书。',15,C.ink)+text(607,505,'凛还记得，你说雨停后想沿着街边慢慢走回去。',15,C.ink)+line(607,531,1251,531);
  s+=text(624,561,'那时你说',12,C.muted)+rect(608,548,3,83,C.warm,1)+text(624,590,'“还记得我们在书屋一起躲雨的那个晚上吗？',15,'#d2dce8')+text(624,618,'  雨停以后，我们还沿着街边走了一会儿。”',15,'#d2dce8');
  s+=icon('clock',608,660,15,C.faint)+text(632,673,'10月04日 21:18  ·  历史对话',12,C.muted);
  s+=button(582,730,165,'查看原对话',true,'up')+button(761,730,164,'纠正这条记录')+text(1249,756,'忘记',13,C.red,400,'text-anchor="end"');
  s+=line(164,787,1276,787)+icon('memory',165,807,16,C.faint)+text(191,820,'旧对话里的有效经历，也会参与查找。',12,C.faint)+text(1276,820,'仅显示当前伙伴与存档的回忆',12,C.faint,400,'text-anchor="end"');
  return svg('GD Pal · 跨会话回忆检索',s);
}
function relationship(){
  let s=shell('memory')+memoryHeader(4);
  s+=text(164,282,'把相处过的细节，慢慢留下来。',21,C.ink,500)+text(164,311,'称呼、习惯和约定，会随着你们的聊天延续。',13,C.muted)+pill(1163,278,113,'随对话更新',C.green,'#253c3b');
  s+=text(164,355,'我们的相处',14,C.muted,500)+text(748,355,'我们的约定',14,C.muted,500)+pill(1117,338,75,'进行中 2',C.warm,'#373431')+pill(1203,338,73,'已完成 1',C.muted,'#243243');
  s+=rect(164,375,550,115,'#1e2c3d',10,C.line)+icon('user',185,397,19,C.blue)+text(216,413,'你希望她这样称呼你',12,C.muted)+text(185,456,'阿林',27,C.ink,600)+source(572,464,'查看来源');
  s+=rect(164,507,550,117,'#1b2838',10,C.line)+text(185,536,'相处方式',12,C.muted)+text(185,567,'像老朋友一样，随意一点。',17,C.ink,500)+text(185,600,'“以后就别这么客气啦。”',12,C.faint)+source(572,600,'查看来源');
  s+=rect(164,641,550,117,'#1b2838',10,C.line)+text(185,670,'共同习惯',12,C.muted)+text(185,700,'睡前聊聊今天的小事',17,C.ink,500)+text(185,736,'“以后每天睡前聊聊今天的事吧。”',12,C.faint)+source(572,736,'查看来源');
  s+=rect(748,375,528,133,'#202d3a',10,C.line)+dot(772,404,C.warm,4)+text(789,410,'周末一起画窗外的树',17,C.ink,500)+text(771,443,'“等周末，我们一起画画吧。”',13,C.muted)+source(770,487,'查看约定的对话')+text(1251,487,'还没完成',12,C.warm,400,'text-anchor="end"');
  s+=rect(748,525,528,133,'#1b2838',10,C.line)+dot(772,554,C.warm,4)+text(789,560,'下次接着读那本书',17,C.ink,500)+text(771,593,'“下次继续读还没看完的那一章。”',13,C.muted)+source(770,637,'查看约定的对话')+text(1251,637,'还没完成',12,C.warm,400,'text-anchor="end"');
  s+=rect(748,675,528,83,'#1c2d32',10,'#344b4c')+icon('check',770,696,20,C.green)+text(802,712,'给书屋的小猫取名字',16,'#b8c9d4',500)+text(802,739,'已完成 · 10月06日',12,C.green)+source(1135,726,'查看来源');
  s+=line(164,787,1276,787)+icon('link',166,806,16,C.faint)+text(192,820,'每一项都有对应的对话来源；需要更正时，可以回到那段对话。',12,C.faint);
  return svg('GD Pal · 稳定关系与约定',s);
}
function presetCard(x,label,sub,selected=false){return rect(x,299,194,67,selected?'#2a4056':'#1b2838',9,selected?'#7298bb':C.line)+text(x+15,326,label,15,selected?C.ink:C.muted,selected?600:400)+text(x+15,350,sub,11,selected?C.blue:C.faint)+(selected?icon('check',x+163,311,17,C.blue):'');}
function profile(){
  let s=shell('user')+heading('伙伴档案 · 凛','调整交流的节奏，让每次见面都能接着上次聊。')+tabs(['外观','光照','画质','人设','扮演规则','桌面行为'],4,[85,85,85,85,120,120]);
  s+=rect(164,256,242,502,'url(#portrait)',12,'#3d526a')+image(portrait,146,279,285,406,'clip-path="url(#portrait-clip)"')+pill(180,272,77,'外观预览',C.blue,'#213244');
  s+=rect(165,632,240,125,'#1b2b3b',0)+text(284,674,'凛',25,C.ink,500,'text-anchor="middle"')+text(284,702,'随时回来，继续上次的话题。',12,C.muted,400,'text-anchor="middle"')+text(284,738,'更换外观  →',12,C.blue,400,'text-anchor="middle"');
  s+=text(438,280,'陪伴预设',18,C.ink,600)+text(1276,280,'填入选项后，保存档案生效',12,C.faint,400,'text-anchor="end"');
  s+=presetCard(438,'长期陪伴','主动交流 · 延续记忆',true)+presetCard(644,'安静陪伴','更少打扰，跟随话题')+presetCard(850,'共同讲故事','一起拓展故事经历')+presetCard(1056,'严谨设定','重要变化先问清楚');
  s+=field(438,405,400,'对话主动程度','主动',true)+field(864,405,412,'澄清倾向','仅必要时',true)+line(438,487,1276,487);
  s+=text(438,519,'对话与记忆衔接',18,C.ink,600)+text(438,553,'自动接续新一段对话',15,C.ink)+text(438,579,'对话变长时自然衔接，回忆与相处约定会继续保留。',12,C.muted)+toggle(1219,536,true);
  s+=field(438,618,400,'换段阈值','120,000')+text(819,661,'tokens',12,C.faint,400,'text-anchor="end"')+field(864,618,412,'交接原文预算','12,000')+text(1257,661,'tokens',12,C.faint,400,'text-anchor="end"');
  s+=rect(438,701,838,46,'#1a2736',8,C.line)+text(454,730,'更多上下文设置',13,C.muted)+text(651,730,'模型容量、场景换段',12,C.faint)+icon('down',1239,715,18,C.muted);
  s+=line(164,771,1276,771)+dot(445,813,C.warm,3)+text(458,818,'有未保存的更改',12,C.muted)+button(986,790,111,'取消')+button(1111,790,165,'保存伙伴档案',true);
  return svg('GD Pal · 长期陪伴预设',s);
}
const pages=[['01-embedding-settings','记忆检索设置',connections()],['02-memory-search','旧回忆搜索',recall()],['03-relationship','相处档案',relationship()],['04-companion-preset','陪伴预设',profile()]];
for(const [name,,content] of pages) fs.writeFileSync(path.join(out,name+'.svg'),content,'utf8');
let board=rect(0,0,3000,2030,'#090f17',0)+text(48,59,'GD PAL  /  记忆与陪伴',28,C.ink,600)+text(2952,57,'UI 预览 · 2026.10.12',16,C.muted,400,'text-anchor="end"');
pages.forEach(([name,title,content],i)=>{const x=48+(i%2)*1476, y=116+Math.floor(i/2)*958;board+=text(x,y,`0${i+1}  ${title}`,20,C.blue,500)+image('data:image/svg+xml;base64,'+Buffer.from(content).toString('base64'),x,y+22,1428,892.5);});
fs.writeFileSync(path.join(out,'overview.svg'),svg('GD Pal 记忆与陪伴 UI 总览',board,3000,2030));
async function render(){
  const modulePath=process.env.GD_PAL_SHARP_MODULE;
  if(!modulePath){console.log('Generated 4 standalone SVG screens and overview.svg');return;}
  const sharp=require(modulePath);
  for(const [name] of pages) await sharp(path.join(out,name+'.svg')).png().toFile(path.join(out,name+'.png'));
  await sharp(path.join(out,'overview.svg')).resize({width:2400}).png().toFile(path.join(out,'overview.png'));
  console.log('Generated 4 SVG screens, PNG previews and overview.');
}
render().catch(error=>{console.error(error.message);process.exitCode=1;});
