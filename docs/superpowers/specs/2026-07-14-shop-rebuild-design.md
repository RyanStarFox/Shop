# Shop! 三端修复与体验重建设计

日期：2026-07-14

## 目标

在保留纯 Swift、SwiftUI、SwiftData 和自定义 WebDAV 的前提下，将 Shop! 修复为可构建、可靠同步、三端体验一致的购物清单应用。

交付范围包括：

- 修复 iOS、macOS、watchOS 与共享包的编译、资源和工程配置问题。
- 修复物品与 Tag 的增删改同步，支持离线修改、删除传播和最后修改者生效。
- iPhone 与 Watch 自动同步；iPhone 与 Mac 通过 WebDAV 自动及手动同步。
- 重做三端界面，采用“克制的原生感”：自然绿色、轻量玻璃层级、内容优先。
- 支持浅色、深色、暗色图标、本地化、Dynamic Type、VoiceOver 和系统交互规范。
- 补充核心数据、同步、撤回和主要界面行为测试。

## 非目标

- 不支持 iOS 15；最低版本保持 iOS 18、macOS 15、watchOS 11。
- 不引入账号系统、自有云服务或 CloudKit。
- 不实现多人协同、复杂 CRDT 或逐条冲突选择界面。
- Watch 不提供 Tag 新建、改名、改色和复杂筛选。

## 产品行为

### 清单

- 未完成物品显示在主清单上方。
- 已完成物品即归档物品，显示在同一页面下方；用户向下滚动即可查看。
- 点击圆圈、向左滑或向右滑可完成物品；归档区采用相同行为恢复物品。
- 点击整行打开编辑界面，可修改名称和 Tag。
- 物品可以没有 Tag，也可以关联多个 Tag。
- 完成、恢复、删除和 Tag 删除后显示可撤回提示。

### Tag

- iPhone 和 Mac 均支持新增、改名、改色和删除 Tag。
- 删除 Tag 不删除物品，只解除关联。
- Watch 显示现有 Tag，并允许在添加物品时选择 Tag，不提供 Tag 管理。

### 同步

- 本地修改后进行短时间防抖，再自动同步。
- 设置中保留“立即同步”、同步中状态、上次成功时间和可恢复错误提示。
- Mac 与 iPhone 离线修改同一记录时，保留 `updatedAt` 更新较晚的一方。
- 删除通过墓碑传播，不能因另一端仍保留旧记录而复活。

## 数据架构

继续使用 SwiftData，但将职责拆分为可测试边界：

- `ShoppingStore`：SwiftData 读写、查询、排序和事务。
- `SyncSnapshotCodec`：模型与稳定 JSON DTO 的转换。
- `SnapshotMerger`：纯值类型合并算法，不依赖网络或 SwiftData。
- `SyncCoordinator`：统一自动同步、防抖、状态与错误。
- `WebDAVTransport`：WebDAV GET/PUT、认证、ETag 和重试。
- `WatchConnectivityTransport`：WatchConnectivity 发送与离线交付。
- `UndoCoordinator`：保存最近可撤回动作并执行反向更新。

现有 `DataStore` 的 UI 状态、持久化、同步编码和过滤职责将被拆开，避免继续形成单一巨型对象。

### 模型字段

`ShoppingItem`：

- `id: UUID`
- `name: String`
- `isCompleted: Bool`
- `createdAt: Date`
- `completedAt: Date?`
- `updatedAt: Date`
- `deletedAt: Date?`
- `sortOrder: Int`
- `tags: [Tag]`

`Tag`：

- `id: UUID`
- `name: String`
- `colorHex: String`
- `createdAt: Date`
- `updatedAt: Date`
- `deletedAt: Date?`

JSON 快照包含格式版本、生成时间、物品和 Tag。读取旧版快照时补齐缺失字段，以兼容已有 `shop_sync.json`。

## 合并规则

快照按稳定 ID 合并：

1. 仅一侧存在记录时保留该记录。
2. 两侧都有记录时，`updatedAt` 较新的一侧获胜。
3. `updatedAt` 相同但内容不同，使用稳定设备 ID 作为确定性平局规则，避免反复翻转。
4. `deletedAt` 属于记录版本的一部分；较新的删除覆盖较旧内容。
5. Tag 合并先执行，再重建物品关系；已删除或不存在的 Tag ID 被忽略。
6. 墓碑保留足够长的清理周期，只有在成功同步并超过保留期后才物理删除。

所有撤回操作都生成新的 `updatedAt`，因此即使原动作已同步，恢复状态仍会向其他设备传播。

## WebDAV 数据流

1. GET `shop_sync.json`，读取内容与 ETag。
2. 将远端快照与本地快照合并。
3. 在本地事务中应用合并结果。
4. 使用 `If-Match` 携带 ETag PUT 合并后的快照。
5. 若返回 412，重新 GET、合并并有限次数重试。
6. 远端文件不存在时使用 `If-None-Match: *` 创建。

服务地址、用户名可保存在偏好设置中；密码存入 Keychain，不再明文写入 `UserDefaults`。默认只接受 HTTPS，HTTP 必须明确提示风险，不开启全局任意网络加载。

## WatchConnectivity 数据流

- 可达时使用 `sendMessage` 提供即时反馈。
- 使用 `updateApplicationContext` 保存最新完整快照，保证不可达时最终送达。
- 激活、可达性恢复和 App 回到前台时请求或推送同步。
- 所有收到的数据都进入同一个 `SnapshotMerger`，不单独实现 Watch 合并规则。
- 控制快照大小；达到消息限制时切换文件传输或压缩快照。

## 界面设计

### 视觉系统

- 采用自然绿色作为主色，系统语义色表达成功、危险与次级信息。
- 使用系统字体和 4/8pt 间距体系。
- iOS 26、macOS 26、watchOS 26 及以上使用原生 Liquid Glass API。
- 较旧受支持系统使用 Material、轻描边和低强度阴影降级。
- 不使用大面积装饰性光斑和重模糊，清单内容保持最高视觉优先级。
- 所有颜色通过语义 token 适配浅色与深色，不在页面中散落硬编码颜色。

### iPhone / iPad

- 顶部显示标题、待购买数量、搜索和主要添加按钮。
- 主清单与归档区位于同一滚动容器。
- 行内展示名称和紧凑 Tag；完成状态不只依赖颜色表达。
- 点击行打开编辑 sheet；圆圈和滑动负责完成或恢复。
- 撤回使用不阻塞内容的底部浮层，并支持 VoiceOver 公告。
- 筛选使用适合小屏的菜单或分组列表，不使用六项拥挤的 segmented control。

### Mac

- 使用原生 `NavigationSplitView`。
- 侧栏提供状态筛选、Tag 筛选和同步状态。
- 主区域展示清单；选中物品后在详情区域编辑名称和 Tag。
- 支持新增、搜索、删除、撤回和常用键盘快捷键。
- Tag 管理能力与 iPhone 保持一致。

### Apple Watch

- 首页显示待购买物品，归档内容置后。
- 支持完成、恢复和快速添加。
- 添加界面可以选择已有 Tag。
- 交互保持短路径，不承载 WebDAV 设置和 Tag 管理。

## 外观与图标

- `appearanceMode` 在 App 根部映射为系统、浅色或深色方案。
- App Icon 资源补齐 iOS、macOS 和 watchOS 所需尺寸。
- iOS 18 的图标外观优先使用资产目录的浅色、深色和 tinted variants；不以手动备用图标切换冒充系统暗色图标。
- 如果保留备用图标功能，单独作为用户选择，不与系统主题强制绑定。

## 错误处理

- 移除持久化和编码路径中的静默 `try?`。
- 对初始化失败、保存失败、无效快照、认证失败、网络超时、ETag 冲突分别提供类型化错误。
- UI 显示可执行的恢复操作，例如重新同步、检查凭据或保留本地副本。
- 自动同步失败不阻止本地编辑，并在下一次触发时重试。
- 同一时刻只允许一个同步任务；新触发合并到当前或下一轮任务。

## 无障碍与本地化

- 所有图标按钮提供可理解的 accessibility label 和 hint。
- 物品行声明名称、Tag 和完成状态。
- 所有触控目标至少 44×44pt。
- 支持 Dynamic Type、最大字号、减少动态效果和高对比度。
- 移除硬编码中英文，统一由 ShopCore 的本地化键提供。
- 中英文均覆盖错误、同步、归档、撤回和编辑流程。

## 工程与代码质量

- 修复 Swift Package 中不存在的资源目录声明。
- 修复 `PlatformColor` 与 SwiftUI `Color` 的错误混用，颜色 DTO 与平台呈现分离。
- 补齐资源目录、图标、scheme、Watch 嵌入和测试 target 配置。
- 抽取共享的 Tag 色板、筛选定义、同步状态和本地化键。
- 删除未使用状态与误导性 UI，保持平台 UI 原生而非强制共享视图代码。
- README 只描述真实存在且通过验证的能力。

## 测试策略

### 单元测试

- 物品与 Tag CRUD、过滤、排序和关系更新。
- 新增、编辑、完成、恢复、删除与撤回。
- 新旧 JSON 快照编解码。
- 最后修改者获胜、平局规则、删除墓碑、Tag 关系重建。
- 墓碑清理条件。

### 传输测试

- WebDAV 200、201、404、401、412、超时与无效 JSON。
- ETag 冲突重试和首次文件创建。
- Watch 即时发送、application context 离线交付和重复消息幂等。

### 界面与构建验证

- iOS、macOS、watchOS 三个 scheme 无签名构建。
- 浅色、深色和系统模式。
- 小屏 iPhone、iPad、Mac 窗口缩放和 Watch 尺寸。
- 最大 Dynamic Type、VoiceOver、减少动态效果。
- 完成/恢复、编辑、滑动、归档滚动、Tag 管理和撤回流程。

## 实施顺序

1. 恢复可构建基线：包资源、导入、颜色类型、资产和工程配置。
2. 添加失败测试并重构数据模型、快照编码与合并器。
3. 实现 WebDAV ETag 同步、Keychain 和自动同步协调。
4. 实现 WatchConnectivity 最终交付与自动触发。
5. 建立视觉 token 和共享交互状态。
6. 重做 iPhone/iPad、Mac、Watch 界面。
7. 补齐图标、本地化、无障碍和文档。
8. 完成三端构建、测试和手动验收。

## 验收标准

- 三个平台均可从干净 checkout 构建。
- 新增、编辑、完成、恢复、删除和 Tag 变更可在对应设备间传播。
- 离线并发修改遵循最后修改者生效，删除记录不会意外复活。
- 自动同步不阻塞本地操作，手动同步可显示明确状态与错误。
- 主清单和归档区处于同一页面，指定手势、编辑和撤回行为均可用。
- 三端视觉遵循选定的 A 方向，并通过浅色、深色、无障碍和本地化检查。
