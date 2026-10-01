import 'package:flutter/material.dart';
import 'package:koi_ui/koi_ui.dart';

/// Exercises Material controls without overriding their component styles.
class StandardComponentCatalog extends StatefulWidget {
  const StandardComponentCatalog({super.key});

  @override
  State<StandardComponentCatalog> createState() =>
      _StandardComponentCatalogState();
}

class _StandardComponentCatalogState extends State<StandardComponentCatalog>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 6, vsync: this)
    ..addListener(_onTabChanged);
  final _menuFocus = FocusNode();
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _search = TextEditingController();
  bool _notifications = true;
  bool _agreement = false;
  bool _banner = false;
  bool _ascending = true;
  String _delivery = '即时';
  String _role = '成员';
  String _view = '列表';
  String _status = '操作后会在这里显示结果';
  String _workspace = '产品设计';
  String _sort = '最近更新';
  double _progress = 0.4;
  int _page = 0;
  final _filters = <String>{'资料'};
  final _selectedDocuments = <String>{};

  void _onTabChanged() => setState(() {});

  @override
  void dispose() {
    _tabs.dispose();
    _menuFocus.dispose();
    _name.dispose();
    _search.dispose();
    super.dispose();
  }

  void _report(String message) => setState(() => _status = message);

  @override
  Widget build(BuildContext context) => Material(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TabBar(
          controller: _tabs,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: const [
            Tab(text: '操作'),
            Tab(text: '输入'),
            Tab(text: '选择'),
            Tab(text: '导航'),
            Tab(text: '数据'),
            Tab(text: '反馈'),
          ],
        ),
        Expanded(
          child: IndexedStack(
            index: _tabs.index,
            children: [
              _pageContent(0, 'actions', _actions()),
              _pageContent(1, 'inputs', _inputs()),
              _pageContent(2, 'selection', _selection()),
              _pageContent(3, 'navigation', _navigation()),
              _pageContent(4, 'data', _data()),
              _pageContent(5, 'feedback', _feedback()),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(KoiSpace.md),
          child: Semantics(liveRegion: true, child: Text(_status)),
        ),
      ],
    ),
  );

  Widget _pageContent(int index, String name, List<Widget> children) =>
      ExcludeFocus(
        excluding: _tabs.index != index,
        child: ListView(
          key: PageStorageKey('catalog-$name'),
          primary: false,
          padding: const EdgeInsets.all(KoiSpace.md),
          children: [
            for (final child in children) ...[
              child,
              const SizedBox(height: KoiSpace.lg),
            ],
          ],
        ),
      );

  List<Widget> _actions() => [
    KoiSection(
      title: const Text('按钮与操作'),
      description: const Text('用清晰的强调层级表达主要操作、次要操作和辅助操作。'),
      child: Wrap(
        spacing: KoiSpace.sm,
        runSpacing: KoiSpace.sm,
        children: [
          FilledButton.icon(
            onPressed: () => _report('主要操作已执行'),
            icon: const Icon(Icons.add),
            label: const Text('主要操作'),
          ),
          FilledButton.tonal(
            onPressed: () => _report('次要操作已执行'),
            child: const Text('次要操作'),
          ),
          OutlinedButton(
            onPressed: () => _report('边框操作已执行'),
            child: const Text('边框操作'),
          ),
          TextButton(
            onPressed: () => _report('辅助操作已执行'),
            child: const Text('辅助操作'),
          ),
          const FilledButton(onPressed: null, child: Text('暂不可用')),
          IconButton(
            tooltip: '刷新目录',
            onPressed: () => _report('目录已刷新'),
            icon: const Icon(Icons.refresh_outlined),
          ),
        ],
      ),
    ),
    KoiSection(
      title: const Text('菜单与提示'),
      child: Wrap(
        spacing: KoiSpace.sm,
        runSpacing: KoiSpace.sm,
        children: [
          MenuAnchor(
            childFocusNode: _menuFocus,
            menuChildren: [
              MenuItemButton(
                leadingIcon: const Icon(Icons.copy_outlined),
                onPressed: () => _report('已选择复制链接'),
                child: const Text('复制链接'),
              ),
              MenuItemButton(
                leadingIcon: const Icon(Icons.archive_outlined),
                onPressed: () => _report('已选择归档资料'),
                child: const Text('归档资料'),
              ),
              const MenuItemButton(child: Text('无权限的操作')),
            ],
            builder: (context, controller, child) => OutlinedButton(
              focusNode: _menuFocus,
              onPressed: () =>
                  controller.isOpen ? controller.close() : controller.open(),
              child: const Text('资料菜单'),
            ),
          ),
          PopupMenuButton<String>(
            tooltip: '更多操作',
            onSelected: (value) => _report('已选择$value'),
            itemBuilder: (context) => const [
              PopupMenuItem(value: '下载副本', child: Text('下载副本')),
              PopupMenuItem(value: '查看活动', child: Text('查看活动')),
              PopupMenuItem(enabled: false, child: Text('删除受保护资料')),
            ],
            icon: const Icon(Icons.more_horiz),
          ),
          const Tooltip(
            message: '操作会保留你的当前选择',
            child: IconButton(onPressed: null, icon: Icon(Icons.help_outline)),
          ),
        ],
      ),
    ),
  ];

  List<Widget> _inputs() => [
    Form(
      key: _form,
      child: KoiSection(
        title: const Text('成员资料'),
        description: const Text('提交时显示校验结果；未完成的输入会保留。'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              key: const ValueKey('catalog-name'),
              controller: _name,
              decoration: const InputDecoration(
                labelText: '成员姓名',
                hintText: '输入中文或英文姓名',
                helperText: '这是其他成员看到的名称',
              ),
              validator: (value) =>
                  value == null || value.trim().isEmpty ? '请输入成员姓名' : null,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: KoiSpace.md),
            DropdownMenu<String>(
              key: const ValueKey('catalog-role'),
              initialSelection: _role,
              expandedInsets: EdgeInsets.zero,
              label: const Text('工作区角色'),
              dropdownMenuEntries: const [
                DropdownMenuEntry(value: '成员', label: '成员'),
                DropdownMenuEntry(value: '管理员', label: '管理员'),
                DropdownMenuEntry(value: '访客', label: '访客'),
              ],
              onSelected: (value) => setState(() => _role = value ?? _role),
            ),
            const SizedBox(height: KoiSpace.md),
            TextFormField(
              enabled: false,
              initialValue: '由组织统一管理',
              decoration: const InputDecoration(labelText: '组织名称'),
            ),
            const SizedBox(height: KoiSpace.md),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: FilledButton(
                onPressed: () {
                  if (_form.currentState!.validate()) {
                    _report('已保存 ${_name.text.trim()} · $_role');
                  }
                },
                child: const Text('保存成员'),
              ),
            ),
          ],
        ),
      ),
    ),
    KoiSection(
      title: const Text('搜索'),
      child: SearchBar(
        controller: _search,
        hintText: '搜索组件名称',
        leading: const Icon(Icons.search),
        onChanged: (value) => _report(value.isEmpty ? '已清空搜索' : '正在搜索：$value'),
        trailing: [
          IconButton(
            tooltip: '清空搜索',
            onPressed: () {
              _search.clear();
              _report('已清空搜索');
            },
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    ),
  ];

  List<Widget> _selection() => [
    KoiSection(
      title: const Text('偏好与单选'),
      child: Column(
        children: [
          SwitchListTile(
            title: const Text('接收更新通知'),
            subtitle: const Text('工作区有更新时提醒我'),
            value: _notifications,
            onChanged: (value) => setState(() => _notifications = value),
          ),
          CheckboxListTile(
            title: const Text('允许成员发表评论'),
            value: _agreement,
            onChanged: (value) => setState(() => _agreement = value!),
          ),
          const SwitchListTile(
            title: Text('组织已锁定的偏好'),
            value: false,
            onChanged: null,
          ),
          RadioGroup<String>(
            groupValue: _delivery,
            onChanged: (value) => setState(() => _delivery = value!),
            child: const Column(
              children: [
                RadioListTile(value: '即时', title: Text('即时提醒')),
                RadioListTile(value: '摘要', title: Text('每日摘要')),
              ],
            ),
          ),
        ],
      ),
    ),
    KoiSection(
      title: const Text('筛选与视图'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: KoiSpace.sm,
            runSpacing: KoiSpace.sm,
            children: [
              for (final filter in ['资料', '图片', '视频'])
                FilterChip(
                  label: Text(filter),
                  selected: _filters.contains(filter),
                  onSelected: (selected) => setState(() {
                    selected ? _filters.add(filter) : _filters.remove(filter);
                  }),
                ),
            ],
          ),
          const SizedBox(height: KoiSpace.md),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SegmentedButton<String>(
              segments: const [
                ButtonSegment(
                  value: '列表',
                  label: Text('列表'),
                  icon: Icon(Icons.view_list_outlined),
                ),
                ButtonSegment(
                  value: '网格',
                  label: Text('网格'),
                  icon: Icon(Icons.grid_view_outlined),
                ),
              ],
              selected: {_view},
              onSelectionChanged: (value) =>
                  setState(() => _view = value.single),
            ),
          ),
          const SizedBox(height: KoiSpace.sm),
          Text('显示：${_filters.isEmpty ? '无' : _filters.join('、')} · $_view'),
        ],
      ),
    ),
    KoiSection(
      title: const Text('数值与进度预览'),
      description: const Text('拖动滑块，查看不同完成比例的显示。'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            container: true,
            label: '预览进度',
            child: Slider(
              value: _progress,
              divisions: 10,
              label: '${(_progress * 100).round()}%',
              semanticFormatterCallback: (value) => '${(value * 100).round()}%',
              onChanged: (value) => setState(() => _progress = value),
            ),
          ),
          LinearProgressIndicator(
            value: _progress,
            semanticsLabel: '线性进度预览',
            semanticsValue: '${(_progress * 100).round()}%',
          ),
          const SizedBox(height: KoiSpace.md),
          Wrap(
            spacing: KoiSpace.md,
            runSpacing: KoiSpace.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              CircularProgressIndicator(
                value: _progress,
                semanticsLabel: '环形进度预览',
                semanticsValue: '${(_progress * 100).round()}%',
              ),
              Text('当前预览：${(_progress * 100).round()}%'),
            ],
          ),
        ],
      ),
    ),
  ];

  List<Widget> _navigation() => [
    KoiSection(
      title: const Text('页面导航'),
      description: const Text('选择入口后显示对应内容；返回其他分类时保持位置。'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          NavigationBar(
            selectedIndex: _page,
            onDestinationSelected: (value) => setState(() => _page = value),
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.description_outlined),
                selectedIcon: Icon(Icons.description),
                label: '资料',
              ),
              NavigationDestination(
                icon: Icon(Icons.check_circle_outline),
                selectedIcon: Icon(Icons.check_circle),
                label: '任务',
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: KoiSpace.lg),
            child: Text(_page == 0 ? '资料页面：最近更新的工作区文件' : '任务页面：需要处理的待办事项'),
          ),
        ],
      ),
    ),
  ];

  List<Widget> _data() {
    final documents = ['交互规范.md', '发布检查清单.md', '组件使用说明.md']
      ..sort((a, b) => _ascending ? a.compareTo(b) : b.compareTo(a));
    return [
      KoiSection(
        title: const Text('资料表格'),
        description: const Text('支持排序、多选；窄窗口可横向滚动查看所有列。'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SingleChildScrollView(
              key: const ValueKey('catalog-table-scroll'),
              scrollDirection: Axis.horizontal,
              child: DataTable(
                sortColumnIndex: 0,
                sortAscending: _ascending,
                onSelectAll: (selected) => setState(() {
                  _selectedDocuments.clear();
                  if (selected == true) _selectedDocuments.addAll(documents);
                }),
                columns: [
                  DataColumn(
                    label: const Text('资料名称'),
                    onSort: (_, ascending) =>
                        setState(() => _ascending = ascending),
                  ),
                  const DataColumn(label: Text('维护人')),
                  const DataColumn(label: Text('状态')),
                ],
                rows: [
                  for (final name in documents)
                    DataRow(
                      key: ValueKey(name),
                      selected: _selectedDocuments.contains(name),
                      onSelectChanged: (selected) => setState(() {
                        selected == true
                            ? _selectedDocuments.add(name)
                            : _selectedDocuments.remove(name);
                      }),
                      cells: [
                        DataCell(Text(name)),
                        const DataCell(Text('设计团队')),
                        const DataCell(Text('已更新')),
                      ],
                    ),
                ],
              ),
            ),
            const SizedBox(height: KoiSpace.sm),
            Text('已选择 ${_selectedDocuments.length} 项资料'),
          ],
        ),
      ),
    ];
  }

  List<Widget> _feedback() => [
    KoiSection(
      title: const Text('确认与反馈'),
      description: Text('当前工作区：$_workspace；排序：$_sort'),
      child: Wrap(
        spacing: KoiSpace.sm,
        runSpacing: KoiSpace.sm,
        children: [
          OutlinedButton(onPressed: _rename, child: const Text('重命名工作区')),
          OutlinedButton(
            onPressed: () {
              ScaffoldMessenger.of(context)
                ..hideCurrentSnackBar()
                ..showSnackBar(
                  SnackBar(
                    content: const Text('资料已移至归档'),
                    action: SnackBarAction(
                      label: '撤销',
                      onPressed: () => _report('已撤销归档'),
                    ),
                  ),
                );
            },
            child: const Text('显示短消息'),
          ),
          OutlinedButton(
            onPressed: () => setState(() => _banner = true),
            child: const Text('显示横幅'),
          ),
          OutlinedButton(onPressed: _chooseSort, child: const Text('选择排序')),
        ],
      ),
    ),
    if (_banner)
      MaterialBanner(
        content: const Text('工作区有新的资料版本，当前编辑内容会保留。'),
        actions: [
          TextButton(
            onPressed: () => setState(() {
              _banner = false;
              _status = '稍后查看资料更新';
            }),
            child: const Text('稍后'),
          ),
          TextButton(
            onPressed: () => setState(() {
              _banner = false;
              _status = '正在查看资料更新';
            }),
            child: const Text('查看更新'),
          ),
        ],
      ),
  ];

  Future<void> _rename() async {
    final name = await showDialog<String>(
      context: context,
      builder: (context) => _RenameDialog(name: _workspace),
    );
    if (!mounted || name == null) return;
    setState(() {
      _workspace = name;
      _status = '工作区已重命名为 $name';
    });
  }

  Future<void> _chooseSort() async {
    final selection = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final option in ['最近更新', '名称顺序', '最早创建'])
                ListTile(
                  title: Text(option),
                  selected: option == _sort,
                  trailing: option == _sort ? const Icon(Icons.check) : null,
                  onTap: () => Navigator.pop(context, option),
                ),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('取消排序'),
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || selection == null) return;
    setState(() {
      _sort = selection;
      _status = '排序已切换为 $selection';
    });
  }
}

class _RenameDialog extends StatefulWidget {
  const _RenameDialog({required this.name});

  final String name;

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final _name = TextEditingController(text: widget.name);
  final _form = GlobalKey<FormState>();

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    title: const Text('工作区名称'),
    content: Form(
      key: _form,
      child: TextFormField(
        key: const ValueKey('catalog-rename'),
        controller: _name,
        decoration: const InputDecoration(labelText: '名称'),
        validator: (value) =>
            value == null || value.trim().isEmpty ? '名称不能为空' : null,
      ),
    ),
    actions: [
      TextButton(
        autofocus: true,
        onPressed: () => Navigator.pop(context),
        child: const Text('取消重命名'),
      ),
      FilledButton(
        onPressed: () {
          if (_form.currentState!.validate()) {
            Navigator.pop(context, _name.text.trim());
          }
        },
        child: const Text('确认重命名'),
      ),
    ],
  );
}
