export function authErrorMessage(code?: string) {
  switch (code) {
    case "invalid_credentials":
      return "メールアドレスまたはパスワードが正しくありません。";
    case "email_not_confirmed":
      return "確認メールのリンクを開いてから、ログインしてください。";
    case "weak_password":
      return "パスワードが安全性の条件を満たしていません。より長く推測しにくいものに変更してください。";
    case "user_already_exists":
    case "email_exists":
      return "登録できませんでした。登録済みの場合はログインしてください。";
    case "over_email_send_rate_limit":
    case "over_request_rate_limit":
      return "しばらく時間をおいてから、もう一度お試しください。";
    case "signup_disabled":
      return "現在、新規登録を受け付けていません。";
    default:
      return "認証できませんでした。接続状況を確認して、もう一度お試しください。";
  }
}
