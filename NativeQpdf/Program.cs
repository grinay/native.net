using System;
using System.Text.Json.Nodes;
using NativeQpdf;

public class Program
{
    public static void Main(string[] args)
    {
        if (args.Length < 2)
        {
            Console.WriteLine("Please provide input and output file paths.");
            return;
        }

        var srcPath = args[0];
        var destFile = args[1];
        
        var json = new JsonObject
        {
            { "empty", "" },
            { "outputFile", destFile },
            {
                "pages", new JsonArray
                {
                    new JsonObject
                    {
                        { "file", srcPath },
                        { "range", "1" }
                    }
                }
            }
        };

        QpdfWrapper.RunFromJSON(json.ToString());
    }
}