import QtQuick
import Quickshell
import ".."

// 算式：在启动器里直接算，不占一个视图。
//
// 求值用 QML 自己的 JS，不起外部进程 —— 本来想交给 `bc`，但这台机器上没装
// （`command -v bc` 空），为一个算式去多一条依赖不值。风险由白名单兜住：
// 除了数字、小数点、括号、空格和下面那几个函数名，一个字符都进不来，
// 所以交给 Function() 的那段里既没有标识符也没有属性访问。
//
// 结果按回车是复制到剪贴板 —— 在启动器里算完数，下一步十有八九是粘到别处。
Addon {
  id: calc
  launcherHint: "算式"
  // 名字 → 真正算的东西。bc 那套 e(x)/l(x) 不搬，用大家认得的写法。
  readonly property var functions: ({
    sqrt: "Math.sqrt", abs: "Math.abs", ln: "Math.log", log: "Math.log10",
    exp: "Math.exp", sin: "Math.sin", cos: "Math.cos", tan: "Math.tan",
    atan: "Math.atan", asin: "Math.asin", acos: "Math.acos", round: "Math.round"
  })

  // 认出算式，顺手把千分位去掉；不是算式就回 ""。应用名里的字母
  // （visual-studio-code）进不来；日期（2024-03-15）当文本；两个以上减号
  // 的（1-2-3）不猜。
  function expression(text) {
    // 末尾的等号当“算！”处理，不是非法字符（很多人输完习惯敲一个 =）。
    var value = String(text || "").trim().replace(/=+$/, "").trim().replace(/[_,，]/g, "")
    if (value === "" || value.length > 120) return ""
    if (/^\d{4}-\d{1,2}-\d{1,2}/.test(value)) return ""
    if ((value.match(/-/g) || []).length > 1) return ""
    var bare = value.replace(/[a-z]+(?=\()/g, function(name) { return functions[name] ? "" : "@" })
    if (/[a-zA-Z@]/.test(bare)) return ""
    if (!/^[0-9()\s.+\-*/%^]*$/.test(bare)) return ""
    if (!/\d/.test(value)) return ""
    if (!/[+\-*/%^]/.test(value) && !/[a-z]+(?=\()/.test(value)) return ""
    return value
  }

  // 算出来；算不出（或者溢出）就回 ""。
  function evaluate(expr) {
    var js = expr.replace(/\^/g, "**")
    var names = Object.keys(functions)
    for (var i = 0; i < names.length; i++)
      js = js.split(names[i] + "(").join(functions[names[i]] + "(")
    var value
    try {
      value = Function('"use strict"; return (' + js + ")")()
    } catch (error) {
      return ""
    }
    if (typeof value !== "number" || !isFinite(value)) return ""
    // 小数位太多是浮点的味道，不是信息；但 1e15 以上双精度自己就开始丢位了，
    // 摊开写反而像在报精确值，所以那个量级改成科学记数。
    if (Math.abs(value) >= 1e15) return value.toExponential(10).replace(/(\.\d*?)0+e/, "$1e").replace(/\.e/, "e")
    var text = String(value)
    if (value !== 0 && text.indexOf(".") !== -1 && text.split(".")[1].length > 10)
      text = String(Math.round(value * 1e10) / 1e10)
    return text
  }

  function copy(result) {
    if (result === "") return
    // 写剪贴板就够了：上游的复制历史会记下它，胶囊自己会冒出来。
    Quickshell.clipboardText = result
    calc.host.view = "rest"
  }

  function launcherRow(text) {
    var expr = calc.expression(text)
    if (expr === "") return null
    var answer = calc.evaluate(expr)
    return {
      // 图标字体里能确定一定在的只有 ASCII，所以上面就是一个等号：
      // “12*7 =” 不用说也懂（新字形没法验形状，不如用保错的）。
      glyph: "=", tile: "#ff9f0a", ink: "#ffffff",
      label: answer === "" ? "算不出来" : answer,
      detail: answer === "" ? expr : expr + "  回车复制",
      first: true,
      run: function() { calc.copy(answer) }
    }
  }
}
