defmodule PolicrMiniBot.Helper do
  @moduledoc """
  机器人功能助手模块，提供和机器人实现相关的各种辅助函数。

  通过 `use PolicrMiniBot, plug: ...` 实现的插件会自动导入本模块的所有函数。
  """

  alias PolicrMini.Logger

  alias PolicrMini.ChatBusiness

  @type tgerror :: {:error, Telegex.Model.errors()}
  @type tgmsg :: Telegex.Model.Message.t()

  @doc """
  获取机器人自身的 `id` 字段。详情参照 `PolicrMiniBot.id/0` 函数。
  """
  defdelegate bot_id, to: PolicrMiniBot, as: :id

  @doc """
  获取机器人自身的 `username` 字段。详情参照 `PolicrMiniBot.username/0` 函数。
  """
  defdelegate bot_username, to: PolicrMiniBot, as: :username

  @doc """
  根据 map 数据构造用户全名。

  如果 fist_name 和 last_name 都不存在，则使用 id。
  """
  @spec fullname(map()) :: String.t()
  def fullname(%{first_name: first_name, last_name: nil}),
    do: first_name

  def fullname(%{first_name: first_name, last_name: last_name}),
    do: "#{first_name} #{last_name}"

  def fullname(%{fullname: fullname}), do: fullname
  def fullname(%{id: id}), do: Integer.to_string(id)

  @doc """
  转义 Markdown 中不能被 Telegram 发送的字符。
  """
  @spec escape_markdown(String.t()) :: String.t()
  def escape_markdown(text) do
    text
    |> String.replace(".", "\\.")
    |> String.replace("+", "\\+")
    |> String.replace("-", "\\-")
    |> String.replace("=", "\\=")
  end

  # 过滤掉关键字列表中的 nil 值
  defp delete_keyword_nils(keyword) when is_list(keyword) do
    keyword |> Enum.filter(fn {_, value} -> value != nil end)
  end

  @time_seeds [0.2, 0.4, 0.8, 1.0]
  @markdown_parse_mode "MarkdownV2"
  @markdown_to_html_parse_mode "MarkdownV2ToHTML"

  @type parsemode :: String.t()

  @type send_message_opts :: [
          {:disable_notification, boolean()},
          {:parse_mode, parsemode() | nil},
          {:disable_web_page_preview, boolean()},
          {:reply_markup, Telegex.Model.InlineKeyboardMarkup.t()},
          {:retry, integer()}
        ]

  @doc """
  发送文本消息。

  如果 `options` 参数中不包含以下配置，将为它们准备默认值：
  - `disable_notification`: `true`
  - `parse_mode`: `"MarkdownV2"`
  - `disable_web_page_preview`: `false`
  - `retry`: 5
  附加的 `retry` 参数表示自动重试次数。一般来讲，重试会发生在网络问题导致发送不成功的情况下，重试次数使用完毕仍然失败则不会继续发送。
  """
  @spec send_message(integer(), String.t(), send_message_opts) :: {:ok, tgmsg} | tgerror()
  def send_message(chat_id, text, options \\ []) do
    options =
      options
      |> Keyword.put_new(:disable_notification, true)
      |> Keyword.put_new(:parse_mode, @markdown_parse_mode)
      |> Keyword.put_new(:disable_web_page_preview, true)
      |> Keyword.put_new(:retry, 5)
      |> delete_keyword_nils()

    parse_mode = Keyword.get(options, :parse_mode)

    {text, options} =
      case parse_mode do
        @markdown_parse_mode ->
          text = escape_markdown(text)
          {text, options}

        @markdown_to_html_parse_mode ->
          text = Telegex.Marked.as_html(text)
          {text, Keyword.put(options, :parse_mode, "HTML")}

        _ ->
          {text, options}
      end

    case Telegex.send_message(chat_id, text, options) do
      {:ok, message} ->
        {:ok, message}

      {:error, %Telegex.Model.RequestError{reason: :timeout}} = e ->
        # 处理重试（减少次数并递归）
        retry = options |> Keyword.get(:retry)

        if retry && retry > 0 do
          Logger.unitized_warn("Message sending timed out, prepare to try again",
            remaining_times: retry - 1,
            chat_id: chat_id
          )

          options = options |> Keyword.put(:retry, retry - 1)
          send_message(chat_id, text, options)
        else
          e
        end

      {:error, %Telegex.Model.Error{description: <<"Too Many Requests: retry after">> <> _rest}} =
          e ->
        retry = options |> Keyword.get(:retry)

        if retry && retry > 0 do
          Logger.unitized_warn("Too many requests are restricted to be sent",
            remaining_times: retry - 1,
            chat_id: chat_id
          )

          options = options |> Keyword.put(:retry, retry - 1)
          :timer.sleep(trunc(800 * retry * Enum.random(@time_seeds)))
          send_message(chat_id, text, options)
        else
          e
        end

      e ->
        e
    end
  end

  @type send_photo_opts :: [
          {:caption, String.t()},
          {:disable_notification, boolean()},
          {:parse_mode, parsemode() | nil},
          {:reply_markup, Telegex.Model.InlineKeyboardMarkup.t()},
          {:retry, integer()}
        ]

  @doc """
  发送图片。

  如果 `options` 参数中不包含以下配置，将为它们准备默认值：
  - `disable_notification`: `true`
  - `parse_mode`: `"MarkdownV2"`
  - `retry`: 5
  附加的 `retry` 参数表示自动重试次数。一般来讲，重试会发生在网络问题导致发送不成功的情况下，重试次数使用完毕仍然失败则不会继续发送。
  """
  @spec send_photo(integer(), String.t(), send_photo_opts) :: {:ok, tgmsg} | tgerror
  def send_photo(chat_id, photo, options \\ []) do
    options =
      options
      |> Keyword.put_new(:disable_notification, true)
      |> Keyword.put_new(:parse_mode, @markdown_parse_mode)
      |> Keyword.put_new(:retry, 5)
      |> delete_keyword_nils()

    parse_mode = Keyword.get(options, :parse_mode)

    options =
      if caption = options[:caption] do
        case parse_mode do
          @markdown_parse_mode ->
            caption = escape_markdown(caption)
            Keyword.put(options, :caption, caption)

          @markdown_to_html_parse_mode ->
            caption = Telegex.Marked.as_html(caption)

            options
            |> Keyword.put(:caption, caption)
            |> Keyword.put(:parse_mode, "HTML")

          _ ->
            options
        end
      else
        options
      end

    case Telegex.send_photo(chat_id, photo, options) do
      {:ok, message} ->
        {:ok, message}

      {:error, %Telegex.Model.RequestError{reason: :timeout}} = e ->
        # 处理重试（减少次数并递归）
        retry = options |> Keyword.get(:retry)

        if retry && retry > 0 do
          Logger.unitized_warn("Message sending timed out, prepare to try again",
            remaining_times: retry - 1,
            chat_id: chat_id
          )

          options = options |> Keyword.put(:retry, retry - 1)
          send_photo(chat_id, photo, options)
        else
          e
        end

      {:error, %Telegex.Model.Error{description: <<"Too Many Requests: retry after">> <> _rest}} =
          e ->
        retry = options |> Keyword.get(:retry)

        if retry && retry > 0 do
          Logger.unitized_warn("Too many requests are restricted to be sent",
            remaining_times: retry - 1,
            chat_id: chat_id
          )

          options = options |> Keyword.put(:retry, retry - 1)
          :timer.sleep(trunc(800 * retry * Enum.random(@time_seeds)))
          send_photo(chat_id, photo, options)
        else
          e
        end

      e ->
        e
    end
  end

  @doc """
  编辑消息。

  如果 `options` 参数中不包含以下配置，将为它们准备默认值：
  - `parse_mode`: `"MarkdownV2"`
  - `disable_web_page_preview`: `false`
  """
  @spec edit_message_text(String.t(), keyword) :: {:ok, tgmsg} | tgerror
  def edit_message_text(text, options \\ []) do
    options =
      options
      |> Keyword.put_new(:parse_mode, @markdown_parse_mode)
      |> Keyword.put_new(:disable_web_page_preview, true)
      |> delete_keyword_nils()

    text =
      if(options |> Keyword.get(:parse_mode) == @markdown_parse_mode) do
        escape_markdown(text)
      else
        text
      end

    Telegex.edit_message_text(text, options)
  end

  @doc """
  回复文本消息。
  其 `message_id` 参数的值会合并到 `options` 参数中的 `reply_to_message_id` 配置中。其余请参考 `send_message/3`
  """
  def reply_message(chat_id, message_id, text, options \\ []) do
    options = options |> Keyword.merge(reply_to_message_id: message_id)

    send_message(chat_id, text, options)
  end

  @default_restrict_permissions %Telegex.Model.ChatPermissions{
    can_send_messages: false,
    can_send_media_messages: false,
    can_send_polls: false,
    can_send_other_messages: false,
    can_add_web_page_previews: false,
    can_change_info: false,
    can_invite_users: false,
    can_pin_messages: false
  }

  @doc """
  删除消息。

  附加的 `options` 参数可配置 `delay_seconds` 实现延迟删除。
  注意，延迟删除无法直接获得请求结果，将直接返回 `:ok`。
  """
  @spec delete_message(integer, integer, [{atom, any}]) :: {:ok, true} | tgerror
  def delete_message(chat_id, message_id, options \\ []) do
    delay_seconds =
      options
      |> Keyword.get(:delay_seconds)

    if delay_seconds do
      delay_seconds = if delay_seconds < 0, do: 0, else: delay_seconds
      async(fn -> Telegex.delete_message(chat_id, message_id) end, seconds: delay_seconds)

      {:ok, true}
    else
      Telegex.delete_message(chat_id, message_id)
    end
  end

  @doc """
  限制聊天成员。

  目前来讲，它会限制以下权限：
  - `can_send_messages`: `false`
  - `can_send_media_messages`: `false`
  - `can_send_polls`: `false`
  - `can_send_other_messages`: `false`
  - `can_add_web_page_previews`: `false`
  - `can_change_info`: `false`
  - `can_invite_users`: `false`
  - `can_pin_messages`: `false`
  """
  def restrict_chat_member(chat_id, user_id) do
    Telegex.restrict_chat_member(chat_id, user_id, @default_restrict_permissions)
  end

  @doc """
  解除聊天成员限制。

  此调用产生的权限修改是动态的，它会将被限制用户的权限恢复为群组记录中的原始权限配置。
  """
  def derestrict_chat_member(chat_id, user_id) do
    {:ok,
     %{
       tg_can_send_messages: can_send_messages,
       tg_can_send_media_messages: can_send_media_messages,
       tg_can_send_polls: can_send_polls,
       tg_can_send_other_messages: can_send_other_messages,
       tg_can_add_web_page_previews: can_add_web_page_previews,
       tg_can_change_info: can_change_info,
       tg_can_invite_users: can_invite_users,
       tg_can_pin_messages: can_pin_messages
     }} = ChatBusiness.get(chat_id)

    Telegex.restrict_chat_member(chat_id, user_id, %Telegex.Model.ChatPermissions{
      can_send_messages: can_send_messages,
      can_send_media_messages: can_send_media_messages,
      can_send_polls: can_send_polls,
      can_send_other_messages: can_send_other_messages,
      can_add_web_page_previews: can_add_web_page_previews,
      can_change_info: can_change_info,
      can_invite_users: can_invite_users,
      can_pin_messages: can_pin_messages
    })
  end

  @doc """
  让机器人显示正常打字的动作。
  """
  @spec typing(integer) :: {:ok, boolean} | tgerror
  def typing(chat_id) do
    Telegex.send_chat_action(chat_id, "typing")
  end

  @type mention_opts :: [
          {:parse_mode, String.t()},
          {:anonymization, boolean()},
          {:mosaic, boolean()}
        ]
  @doc """
  生成提及用户的文本内容。

  参数 `user` 需要满足 `fullname/1` 函数子句的任意条件，同时必须包含 `id` 字段。
  参数 `options` 可包括以下选项：
  - `parse_mode` 默认值为 `"MarkdownV2"`，可配置为 `"HTML"`。
  - `anonymization` 默认值为 `true`，可配置为 `false`。

  注意：`parse_mode` 需要跟 `send_message/3` 中的配置一致，否则最终的消息形式不正确，并且无法对被提及用户产生通知。
  """
  @spec mention(map, mention_opts) :: String.t()
  def mention(%{id: id} = user, options \\ []) do
    options =
      options
      |> Keyword.put_new(:parse_mode, @markdown_parse_mode)
      |> Keyword.put_new(:anonymization, true)
      |> Keyword.put_new(:mosaic, false)

    name =
      if options[:anonymization] do
        to_string(id)
      else
        name = fullname(user)

        if options[:mosaic] do
          mosaic_name(name)
        else
          name
        end
      end

    case options[:parse_mode] do
      "MarkdownV2" -> "[#{Telegex.Marked.escape_text(name)}](tg://user?id=#{id})"
      "HTML" -> ~s(<a href="tg://user?id=#{id}">#{name}</a>)
    end
  end

  @doc """
  给名字打马赛克（模拟）。

  将名字中的部分字符替换成 `░` 符号。如果名字过长（超过五个字符），则只保留前后四个字符，中间使用两个 `█` 填充。
  """
  @spec mosaic_name(String.t()) :: String.t()
  def mosaic_name(name) do
    len = String.length(name)
    mosaic_name(name, len)
  end

  def mosaic_name(name, len) when is_integer(len) and len == 1 do
    name
  end

  def mosaic_name(name, len) when is_integer(len) and len == 2 do
    name
    |> String.graphemes()
    |> Enum.with_index()
    |> Enum.map(fn {char, index} ->
      if index == 1, do: "░", else: char
    end)
    |> Enum.join("")
  end

  def mosaic_name(name, len) when is_integer(len) and len >= 3 and len <= 5 do
    last_index = len - 1

    name
    |> String.graphemes()
    |> Enum.with_index()
    |> Enum.map(fn {char, index} ->
      if index == 0 || index == last_index, do: char, else: "░"
    end)
    |> Enum.join("")
  end

  def mosaic_name(name, len) do
    last_index = len - 1

    "#{String.slice(name, 0..1)}██#{String.slice(name, (last_index - 1)..last_index)}"
  end

  @defaults [
    vmode: :image,
    ventrance: :unity,
    voccasion: :private,
    kmethod: :kick
  ]

  @type default_keys :: :vmode | :ventrance | :voccasion | :kmethod

  @doc """
  获取默认配置。

  当前 `key` 可以是以下值：
  - `:vmode` - 验证方式
  - `:ventrance` - 验证入口
  - `:voccasion` - 验证场合
  - `:kmethod` - 击杀方式
  """
  @spec default!(default_keys) :: any()
  def default!(key) when is_atom(key) do
    if default = @defaults[key] do
      default
    else
      raise RuntimeError,
            "The value of the unknown `key` parameter is in the `default!/1` function"
    end
  end

  @spec t(String.t(), map()) :: String.t()
  @doc """
  使用默认 `locale` 搜索国际化翻译。
  """
  def t(key, values \\ %{}) do
    t(ExI18n.locale(), key, values)
  end

  @doc """
  搜索国际化翻译。

  参数 `locale` 为 `priv/locals` 中 `yml` 文件的名称。
  参数 `values` 用于给翻译字符串中的变量赋值。
  """
  @spec t(String.t(), String.t(), map()) :: String.t()
  def t(locale, key, values)
      when is_binary(locale) and is_binary(key) and is_map(values) do
    try do
      ExI18n.t(locale, key, values)
    rescue
      e ->
        Logger.unitized_error("Translation search", key: key, raises: e)

        "#{locale}:#{key}" |> String.replace("_", "\\_")
    end
  end

  @doc """
  异步执行函数，不指定延迟时间。
  """
  @spec async(function()) :: :ok
  def async(callback) when is_function(callback) do
    TaskAfter.task_after(0, callback)

    :ok
  end

  @doc """
  异步执行函数，可指定单位为秒的延迟时间。
  """
  @spec async(function, [{:seconds, integer}, ...]) :: :ok
  def async(callback, [{:seconds, seconds}]) when is_integer(seconds) and is_function(callback) do
    TaskAfter.task_after(seconds * 1000, callback)

    :ok
  end

  @doc """
  响应回调查询。
  """
  @spec answer_callback_query(String.t(), keyword()) :: :ok | {:error, Telegex.Model.errors()}
  def answer_callback_query(callback_query_id, options \\ []) do
    Telegex.answer_callback_query(callback_query_id, options)
  end

  @doc """
  解析回调中的数据。
  """
  @spec parse_callback_data(String.t()) :: {String.t(), [String.t()]}
  def parse_callback_data(data) when is_binary(data) do
    [_, version | args] = data |> String.split(":")

    {version, args}
  end
end
