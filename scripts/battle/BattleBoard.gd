extends Node3D

# ============================================================
# 桌面布局参数
# ============================================================
const TABLE_W     = 15.0
const TABLE_D     = 9.5
const TABLE_H     = 0.12

const PLAYER_Z    = 3.2
const ENEMY_Z     = -3.2
const PIECE_GAP   = 1.40

# ============================================================
# 战斗参数
# ============================================================
const STRIKE_INTERVAL  = 0.4   # 攻击与反击之间的间隔（秒）
const DEATH_DURATION   = 0.2   # 棋子死亡缩小动画时长（秒）

# ============================================================
# 颜色
# ============================================================
const COLOR_TABLE      = Color(0.22, 0.13, 0.07)
const COLOR_DIVIDER    = Color(0.75, 0.60, 0.15)
const COLOR_PLAYER     = Color(0.18, 0.42, 0.88)
const COLOR_ENEMY      = Color(0.82, 0.16, 0.16)
const COLOR_LABEL      = Color(1.00, 1.00, 1.00)
const COLOR_NEAR_DEATH = Color(0.45, 0.45, 0.45)  # 濒死：灰色

# ============================================================
# 棋子初始数据（攻击力 / 血量）
# ============================================================
var player_data: Array[Dictionary] = [
	{"atk": 2, "hp": 14}, {"atk": 1, "hp": 18}, {"atk": 4, "hp": 10},
	{"atk": 3, "hp": 12}, {"atk": 2, "hp": 16}, {"atk": 5, "hp":  8},
	{"atk": 1, "hp": 14}, {"atk": 3, "hp": 10}, {"atk": 2, "hp": 18},
	{"atk": 4, "hp": 12},
]
var enemy_data: Array[Dictionary] = [
	{"atk": 3, "hp": 12}, {"atk": 2, "hp": 16}, {"atk": 4, "hp":  8},
	{"atk": 1, "hp": 14}, {"atk": 3, "hp": 10}, {"atk": 2, "hp": 14},
	{"atk": 5, "hp":  8}, {"atk": 3, "hp": 12}, {"atk": 1, "hp": 18},
	{"atk": 4, "hp": 10},
]

# ============================================================
# 存活棋子列表（运行时动态维护）
# 每项格式：{ atk, hp, name, index, node:Node3D, label:Label3D, dead:bool }
# ============================================================
var player_alive: Array = []
var enemy_alive:  Array = []

# 当前先手方：每轮随机决定
var player_attacks_first: bool = true

# 回合计数器
var round_count: int = 0


func _ready() -> void:
	setup_camera()
	setup_light()
	create_table()
	create_divider()
	spawn_row(player_data, PLAYER_Z, COLOR_PLAYER, player_alive, "战士")
	spawn_row(enemy_data,  ENEMY_Z,  COLOR_ENEMY,  enemy_alive,  "哥布林")
	start_battle()


# 摄像机：斜俯视，类似 Inscryption 坐在桌边的视角
func setup_camera() -> void:
	var cam := $Camera3D
	cam.position = Vector3(0.0, 9.0, 13.0)
	cam.look_at(Vector3(0.0, 0.0, 0.8), Vector3.UP)


# 方向光：从斜上方照射，产生立体感阴影
func setup_light() -> void:
	var light := $DirectionalLight3D
	light.rotation_degrees = Vector3(-55.0, 25.0, 0.0)
	light.light_energy     = 1.3
	light.shadow_enabled   = true


# 创建深棕木质桌面
func create_table() -> void:
	var node := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	var mat  := StandardMaterial3D.new()
	mesh.size        = Vector3(TABLE_W, TABLE_H, TABLE_D)
	mat.albedo_color = COLOR_TABLE
	node.mesh              = mesh
	node.material_override = mat
	add_child(node)


# 创建中间金色分割线，区分我方/敌方区域
func create_divider() -> void:
	var node := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	var mat  := StandardMaterial3D.new()
	mesh.size        = Vector3(TABLE_W, 0.05, 0.10)
	mat.albedo_color = COLOR_DIVIDER
	node.mesh              = mesh
	node.material_override = mat
	node.position = Vector3(0.0, TABLE_H * 0.5 + 0.025, 0.0)
	add_child(node)


# 生成一整排棋子，同时把棋子数据存入 alive_list，供战斗逻辑使用
func spawn_row(
		data_list:   Array[Dictionary],
		z_pos:       float,
		color:       Color,
		alive_list:  Array,
		name_prefix: String
) -> void:
	var count   := data_list.size()
	var start_x := -(count - 1) * PIECE_GAP * 0.5

	for i in range(count):
		var d := data_list[i]

		var root := Node3D.new()
		root.position = Vector3(
			start_x + i * PIECE_GAP,
			TABLE_H * 0.5 + 0.30,
			z_pos
		)

		# 立方体本体
		var mesh_inst := MeshInstance3D.new()
		var mesh      := BoxMesh.new()
		var mat       := StandardMaterial3D.new()
		mesh.size        = Vector3(0.72, 0.60, 0.72)
		mat.albedo_color = color
		mesh_inst.mesh              = mesh
		mesh_inst.material_override = mat
		root.add_child(mesh_inst)

		# 攻击/血量标签
		var label := Label3D.new()
		label.text         = "%d/%d" % [d["atk"], d["hp"]]
		label.font_size    = 96
		label.pixel_size   = 0.006
		label.modulate     = COLOR_LABEL
		label.outline_size = 12
		label.billboard    = BaseMaterial3D.BILLBOARD_ENABLED
		label.position     = Vector3(0.0, 0.68, 0.0)
		root.add_child(label)

		add_child(root)

		# 把这个棋子的完整信息存入存活列表，战斗逻辑靠这个追踪
		alive_list.append({
			"atk":        d["atk"],
			"hp":         d["hp"],
			"name":       name_prefix + str(i + 1),
			"index":      i,
			"node":       root,
			"label":      label,
			"mesh_inst":  mesh_inst,  # 保存引用，濒死时用于改颜色
			"dead":       false,
			"near_death": false,      # 濒死标记：第一次血量归零后进入此状态
		})


# ============================================================
# 战斗逻辑
# ============================================================

# 启动战斗：直接调用异步主循环（协程，不会阻塞 _ready）
func start_battle() -> void:
	print("===== 战斗开始！=====")
	_run_battle()


# 主战斗循环：每轮随机先手，目标随机选取
# 使用 await 控制节奏，函数会在等待期间挂起，不会卡住游戏
func _run_battle() -> void:
	while not player_alive.is_empty() and not enemy_alive.is_empty():
		round_count += 1
		# 每轮独立随机决定先手（而非交替），模拟炉石的随机先手机制
		player_attacks_first = randi() % 2 == 0

		if player_attacks_first:
			print("【本轮我方先手】")
			# 进攻方：我方最左；目标：敌方随机存活棋子
			await _do_strike(
				player_alive[0],
				enemy_alive[randi() % enemy_alive.size()],
				player_alive, enemy_alive
			)
		else:
			print("【本轮敌方先手】")
			# 进攻方：敌方最左；目标：我方随机存活棋子
			await _do_strike(
				enemy_alive[0],
				player_alive[randi() % player_alive.size()],
				enemy_alive, player_alive
			)

	# while 退出说明至少一方已清空
	check_victory()


# 一次完整交换：进攻方出手 → 等1秒 → 防守方若存活则反击 → 再等1秒
# attacker_list：进攻方的存活列表（反击时若进攻方阵亡，从这里移除）
# defender_list：防守方的存活列表（进攻时若防守方阵亡，从这里移除）
func _do_strike(
		attacker:      Dictionary,
		defender:      Dictionary,
		attacker_list: Array,
		defender_list: Array
) -> void:
	# 进攻方出手
	deal_damage(attacker, defender, defender_list)
	await get_tree().create_timer(STRIKE_INTERVAL).timeout

	# 防守方反击（仅当防守方本次攻击中存活）
	if not defender["dead"]:
		deal_damage(defender, attacker, attacker_list)
		await get_tree().create_timer(STRIKE_INTERVAL).timeout


# 执行一次伤害：扣血 → 首次归零进入濒死 → 二次归零才真正消失
func deal_damage(attacker: Dictionary, defender: Dictionary, defender_list: Array) -> void:
	var dmg: int = attacker["atk"]
	defender["hp"] -= dmg

	print("%s 攻击 %s，造成 %d 点伤害（剩余 %d 血）" % [
		attacker["name"], defender["name"], dmg, maxi(0, defender["hp"])
	])

	if defender["hp"] <= 0:
		if not defender["near_death"]:
			# 第一次血量归零：进入濒死状态
			defender["near_death"] = true
			defender["atk"]        = maxi(1, defender["atk"] / 2)  # 攻击力减半，最低1
			defender["hp"]         = 1                              # 保留1点残血继续战斗
			# 棋子变灰，视觉上标示濒死
			defender["mesh_inst"].material_override.albedo_color = COLOR_NEAR_DEATH
			defender["label"].text = "%d/%d★" % [defender["atk"], defender["hp"]]
			print("  → %s 进入濒死！攻击力减半变为 %d" % [defender["name"], defender["atk"]])
		else:
			# 第二次血量归零：播放缩小动画后彻底消失
			defender["dead"] = true
			defender_list.erase(defender)
			print("  → %s 彻底阵亡！" % defender["name"])
			# Tween：在 DEATH_DURATION 秒内把节点缩小到零，结束后删除节点
			var tween := create_tween()
			tween.tween_property(defender["node"], "scale", Vector3.ZERO, DEATH_DURATION)
			tween.tween_callback(defender["node"].queue_free)
	else:
		defender["label"].text = "%d/%d" % [defender["atk"], defender["hp"]]


# 检测胜负：打印日志并在屏幕中央显示结果
func check_victory() -> void:
	if player_alive.is_empty() and enemy_alive.is_empty():
		print("===== 双方同归于尽！共 %d 回合 =====" % round_count)
		show_result("同归于尽", round_count)
	elif enemy_alive.is_empty():
		print("===== 玩家胜利！共 %d 回合 =====" % round_count)
		show_result("胜  利", round_count)
	elif player_alive.is_empty():
		print("===== 玩家失败！共 %d 回合 =====" % round_count)
		show_result("失  败", round_count)


# 在屏幕中央叠一层 2D Canvas，显示大字结果和回合数
func show_result(result_text: String, rounds: int) -> void:
	# CanvasLayer：在 3D 场景上方叠加 2D UI，不受摄像机影响
	var canvas := CanvasLayer.new()
	add_child(canvas)

	# 半透明黑色背景遮罩，让文字更易读
	var bg := ColorRect.new()
	bg.color = Color(0.0, 0.0, 0.0, 0.55)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	canvas.add_child(bg)

	# 主结果文字（居中大字）
	var title := Label.new()
	title.text = result_text
	title.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	title.grow_horizontal = Control.GROW_DIRECTION_BOTH
	title.grow_vertical   = Control.GROW_DIRECTION_BOTH
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 96)
	title.add_theme_color_override("font_color", Color(1.0, 0.9, 0.2))
	title.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0))
	title.add_theme_constant_override("outline_size", 10)
	canvas.add_child(title)

	# 回合数小字（在主标题正下方）
	var subtitle := Label.new()
	subtitle.text = "战斗持续了  %d  回合" % rounds
	subtitle.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	subtitle.grow_horizontal = Control.GROW_DIRECTION_BOTH
	subtitle.grow_vertical   = Control.GROW_DIRECTION_BOTH
	subtitle.offset_top      = 80   # 向下偏移，避免与主标题重叠
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 36)
	subtitle.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
	subtitle.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0))
	subtitle.add_theme_constant_override("outline_size", 6)
	canvas.add_child(subtitle)
