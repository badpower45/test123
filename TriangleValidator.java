public class TriangleValidator {
    public static void main(String[] args) {
        if (args.length < 3) {
            System.out.println("Please provide three integer arguments.");
            return;
        }

        try {
            int a = Integer.parseInt(args[0]);
            int b = Integer.parseInt(args[1]);
            int c = Integer.parseInt(args[2]);

            if (a <= 0 || b <= 0 || c <= 0) {
                System.out.println("Please provide three positive integers.");
                return;
            }

            boolean isTriangle = (a >= b + c) || (b >= a + c) || (c >= a + b);
            System.out.println(isTriangle);

        } catch (NumberFormatException e) {
            System.out.println("Invalid input. Please provide integers only.");
        }
    }
}
