-- CreateTable
CREATE TABLE "decoder_selectors" (
    "id" VARCHAR(26) NOT NULL,
    "selector" VARCHAR(10) NOT NULL,
    "description" TEXT NOT NULL,
    "signature" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "decoder_selectors_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "tags" (
    "id" TEXT NOT NULL,
    "title" VARCHAR(255) NOT NULL,
    "type" VARCHAR(255) NOT NULL,
    "description" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,
    "decoderId" VARCHAR(26) NOT NULL,

    CONSTRAINT "tags_pkey" PRIMARY KEY ("id")
);

-- AddForeignKey
ALTER TABLE "tags" ADD CONSTRAINT "tags_decoderId_fkey" FOREIGN KEY ("decoderId") REFERENCES "decoder_selectors"("id") ON DELETE CASCADE ON UPDATE CASCADE;
