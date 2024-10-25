// Matrix operations without external dependencies
const MatrixOps = {
  // Multiply two matrices
  multiply: (a, b) => {
    const result = Array(a.length)
      .fill()
      .map(() => Array(b[0].length).fill(0));
    return result.map((row, i) => {
      return row.map((_, j) => {
        return a[i].reduce((sum, elm, k) => sum + elm * b[k][j], 0);
      });
    });
  },

  // Transpose a matrix
  transpose: (matrix) => {
    return matrix[0].map((_, i) => matrix.map((row) => row[i]));
  },

  // Get the minor of matrix at row i and column j
  minor: (matrix, i, j) => {
    const minor = matrix
      .slice(0, i)
      .concat(matrix.slice(i + 1))
      .map((row) => row.slice(0, j).concat(row.slice(j + 1)));
    return minor;
  },

  // Calculate determinant of a matrix
  determinant: (matrix) => {
    if (matrix.length === 1) return matrix[0][0];
    if (matrix.length === 2) {
      return matrix[0][0] * matrix[1][1] - matrix[0][1] * matrix[1][0];
    }
    return matrix[0].reduce((sum, element, i) => {
      return (
        sum +
        element *
          Math.pow(-1, i) *
          MatrixOps.determinant(MatrixOps.minor(matrix, 0, i))
      );
    }, 0);
  },

  // Solve system of linear equations using Cramer's rule
  solve: (A, b) => {
    const det = MatrixOps.determinant(A);
    const n = A.length;
    const x = new Array(n);

    for (let i = 0; i < n; i++) {
      const Ai = A.map((row) => [...row]);
      for (let j = 0; j < n; j++) {
        Ai[j][i] = b[j];
      }
      x[i] = MatrixOps.determinant(Ai) / det;
    }
    return x;
  },
};

const createCoordinateMapper = (sourcePoints, targetPoints) => {
  if (sourcePoints.length < 4) {
    console.warn("Using simplified mapping with less than 4 points");
    // Fall back to simple 2-point mapping if less than 4 points
    if (sourcePoints.length >= 2) {
      const [x1, y1] = sourcePoints[0];
      const [x2, y2] = sourcePoints[1];
      const [u1, v1] = targetPoints[0];
      const [u2, v2] = targetPoints[1];

      const scaleX = (u2 - u1) / (x2 - x1);
      const scaleY = (v2 - v1) / (y2 - y1);
      const offsetX = u1 - x1 * scaleX;
      const offsetY = v1 - y1 * scaleY;

      return (gameX, gameY) => {
        return [gameX * scaleX + offsetX, gameY * scaleY + offsetY];
      };
    }
    throw new Error("At least 2 point pairs are required");
  }

  // Use first 4 points to calculate perspective transform
  const calculateTransform = () => {
    const equations = [];
    const constants = [];

    // Use first 4 points to build equation system
    for (let i = 0; i < 4; i++) {
      const [x, y] = sourcePoints[i];
      const [u, v] = targetPoints[i];

      // Add equations for x coordinate
      equations.push([x, y, 1, 0, 0, 0, -u * x, -u * y]);
      constants.push(u);

      // Add equations for y coordinate
      equations.push([0, 0, 0, x, y, 1, -v * x, -v * y]);
      constants.push(v);
    }

    // Solve for transformation parameters
    const solution = MatrixOps.solve(equations, constants);
    return [
      [solution[0], solution[1], solution[2]],
      [solution[3], solution[4], solution[5]],
      [solution[6], solution[7], 1],
    ];
  };

  // Calculate transformation matrix once
  const transform = calculateTransform();

  // Return coordinate conversion function
  return (gameX, gameY) => {
    const denominator = transform[2][0] * gameX + transform[2][1] * gameY + 1;
    const mapX =
      (transform[0][0] * gameX + transform[0][1] * gameY + transform[0][2]) /
      denominator;
    const mapY =
      (transform[1][0] * gameX + transform[1][1] * gameY + transform[1][2]) /
      denominator;

    return [mapX, mapY];
  };
};

export { createCoordinateMapper };
